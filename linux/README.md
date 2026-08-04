# Running Hearthstone Deck Tracker on Linux

Setup for Debian + GNOME, with Hearthstone installed through the Blizzard app
under [Faugus Launcher](https://github.com/Faugus/faugus-launcher).

## How this works, and why

HDT is a WPF application targeting .NET Framework 4.7.2. WPF has no Linux
implementation and never will, so there is no native Linux build to make. It
does not need one: Hearthstone itself only runs under Wine/Proton anyway, and
HDT works when it runs inside **the same Wine prefix** as the game.

That last part is the whole trick. HDT's `HearthMirror` component reads
Hearthstone's Mono heap with `ReadProcessMemory`, and the overlay tracks the
game window with `FindWindow`/`GetWindowRect`. Both only work between
processes that share a wineserver — that is, the same `WINEPREFIX`. Install
HDT into a separate prefix and it will start, see no game, and track nothing.

So: one prefix, two Windows programs. Everything below is about getting real
.NET into that prefix and launching HDT beside Battle.net.

## What was detected on this machine

| | |
|---|---|
| Prefix | `~/Faugus/battlenet` |
| Runner | Proton-CachyOS Latest (`wine-11.0`) |
| Session | X11 |
| Hearthstone | `C:\Program Files (x86)\Hearthstone` |

Two things about that are worth knowing.

**The session must be X11.** GNOME on Wayland does not let a client place a
window at arbitrary screen coordinates or keep it above another application's
fullscreen window, which is exactly what the overlay does. The Faugus entry
for Battle.net already sets `PROTON_ENABLE_WAYLAND=0`, and the current login
session is X11, so this is already correct. If you switch to a Wayland
session, the tracker windows still work but the in-game overlay will not
position itself properly. Choose "GNOME on Xorg" at the login screen.

**The prefix ships Wine Mono, not .NET.** Wine Mono registers the .NET
Framework registry keys (`NDP\v4\Full\Release = 0x82348`, i.e. 4.8) but
implements **no WPF** — `PresentationFramework.dll` and `PresentationCore.dll`
are absent. HDT crashes on startup against it. Step 2 below replaces it with
the real Microsoft runtime.

`Config.cs` already defaults `HearthstoneDirectory` to
`C:\Program Files (x86)\Hearthstone`, which is where Faugus put the game, so
no path configuration is needed.

## Setup

All scripts read their configuration from `lib.sh` and can be overridden with
environment variables. They use the wine, winetricks, cabextract and 7z that
the Faugus flatpak already bundles, so nothing needs installing on the host.

### 1. Build HDT

WPF cannot be compiled on Linux, so the build runs on a Windows CI runner.

On your fork: **Actions → Build Portable (Unsigned) → Run workflow**. When it
finishes, download the `portable-release` artifact.

This workflow is `.github/workflows/build-linux-portable.yml`, a copy of
upstream's `build-portable.yml` with the DigiCert signing and VSTest steps
removed (they need secrets a fork does not have) and the deprecated
`::set-output` calls replaced.

### 2. Back up the prefix

```sh
cd linux
./01-backup-prefix.sh
```

Saves the registry hives and `drive_c/windows` (~325 MB) to
`~/Faugus/hdt-backups/<timestamp>`. The 12 GB of game data is skipped —
winetricks never writes there. Undo with `./restore-prefix.sh <timestamp>`.

### 3. Install .NET Framework 4.8

```sh
./02-install-dotnet48.sh
```

Removes Wine Mono, installs the real Microsoft runtime, and puts the prefix
back to reporting Windows 10 (the `dotnet48` verb leaves it on Windows 7,
which Battle.net dislikes). It then checks that the WPF assemblies actually
landed and fails loudly if they did not.

Close Battle.net and Hearthstone first; the script refuses to run otherwise.
Expect 10–20 minutes and a ~120 MB download.

**This is the step that goes wrong.** `dotnet48` is a notoriously fragile
winetricks verb. If it fails, restore the backup and try again before
changing anything else.

The script also verifies that the flatpak's Wine and the Proton build are the
same version, and refuses to continue if they are not — a mismatched
`wineboot` would migrate the prefix and break Proton's use of it. Both are
`wine-11.0` right now.

### 4. Install HDT

```sh
./03-install-hdt.sh ~/Downloads/portable-release.zip
```

Unpacks to `~/Faugus/battlenet/drive_c/HDT`, i.e. `C:\HDT` in the prefix. It
handles GitHub's nested artifact zip.

### 5. Auto-start with Battle.net

```sh
./04-hook-faugus.sh
```

Faugus's Battle.net entry already points an "additional application" hook at
`faugus-battlenet.bat`, and that file is empty. The script fills it in so
Faugus launches HDT in the same Proton session as Battle.net.

One manual step remains: in Faugus, right-click Battle.net → Edit → enable
the additional-application option → Save. The script prints this. Editing
`games.json` directly would just be overwritten by the running app.

To start HDT separately instead:

```sh
./run-hdt.sh            # flatpak wine — verified to start HDT
./run-hdt.sh --proton   # umu-run/Proton — currently does not start (see below)
```

Start the game first — HDT attaches to a running Hearthstone.

## Verifying tracking

Getting HDT to *run* and getting it to *track* are two different things, and
only the first is confirmed on this machine.

HDT starts correctly under the flatpak's plain `wine-11.0` — the same build
that installed .NET. Its log shows the runtime and prefix are healthy:

```
HDT: 1.54.4.1, Operating System: Microsoft Windows 11 22000, .NET Framework: 528049
CardDefsManager >> Loaded initial base CardDefs: Count=35320
LogWatcherManager.Start >> Using Hearthstone log directory 'C:\Program Files (x86)\Hearthstone\Logs'
OverlayWindow.SetTopmost >> Hearthstone window not found
```

`528049` is .NET 4.8, the Windows version is the prefix's original Windows 11,
and the Hearthstone directory was auto-detected with no configuration. The
last line is expected with the game closed.

What remains unproven is whether HDT and Hearthstone end up sharing a
wineserver. HearthMirror's `ReadProcessMemory` and the overlay's
`FindWindow`/`GetWindowRect` both require it. Faugus starts Hearthstone under
Proton; `./run-hdt.sh` starts HDT under the flatpak's wine. Same `WINEPREFIX`,
so they *should* attach to one wineserver — both are `wine-11.0` — but that
has not been confirmed with the game actually running.

To confirm, launch Battle.net and Hearthstone from Faugus, get into a game,
then check:

```sh
. ./lib.sh && ps -o pid=,comm= -p $(prefix_pids | tr '\n' ' ')
```

Both Hearthstone and HDT must be listed. Then look at HDT's log for
`Hearthstone window not found` — it should stop appearing once the game is up.
If the tracker stays empty while the game runs, the two are on separate
wineservers and the Faugus `.bat` hook is the path to prefer, since it starts
HDT inside Battle.net's own session.

## Known issues

**HDT does not start under Proton.** `./run-hdt.sh --proton` gets as far as
`Proton: Executable is a unix path, launching with 'umu.exe'` and then the
process never appears — no HDT process, no log, nothing in AppData. The page
faults printed around that point come from the prefix's own startup services
and show up identically even when the executable path is wrong, so they are
not the cause. Root cause not identified. The same binary starts fine under
the flatpak's wine, and .NET survives the attempt intact.

This matters because the Faugus `.bat` hook from step 5 also runs under
Proton, just via `cmd.exe` inside an already-established session rather than
as the top-level process. Whether that difference is enough has not been
tested.

**Proton can delete the .NET installation.** Proton contains this:

```python
if file_exists(prefix + "/drive_c/windows/Microsoft.NET/NETFXRepair.exe") and \
        file_is_wine_builtin_dll(prefix + "/drive_c/windows/system32/mscoree.dll"):
    log("Broken .NET installation detected, switching to wine-mono.")
    shutil.rmtree(prefix + "/drive_c/windows/Microsoft.NET")
```

`NETFXRepair.exe` **is** present after installing .NET 4.8, so the only thing
standing between the prefix and having its entire `Microsoft.NET` directory
deleted is `mscoree.dll` staying a native file rather than a Wine builtin.
It is currently native and has survived several Proton launches. If HDT ever
stops starting, check this first:

```sh
file ~/Faugus/battlenet/drive_c/windows/system32/mscoree.dll
```

It must say `PE32+ executable`. A symlink into the Proton directory means the
runtime is about to be, or has already been, wiped — re-run
`./02-install-dotnet48.sh`.

## Source changes in this fork

Deliberately minimal, so the fork stays easy to rebase on upstream.

- **`Hearthstone Deck Tracker/Utility/LinuxCompat.cs`** (new) — detects Wine
  by probing `ntdll` for the `wine_get_version` export.
- **`Hearthstone Deck Tracker/Utility/Updating/Updater.Default.cs`** — the
  updater is disabled under Wine. It checks *upstream* HearthSim releases, so
  on a fork build it would offer to replace your build with an upstream one,
  and `HDTUpdate.exe` swapping files underneath a running Wine process is a
  good way to corrupt the install. The check sits at the top of
  `CheckForUpdates`, ahead of the `force` parameter, because
  `Core.Initialize` passes `force: true` and would otherwise skip straight
  past a guard placed in `ShouldCheckForUpdates`. The Squirrel updater needs
  no change: it is behind `#if(SQUIRREL)`, and the portable build uses the
  `Release` configuration, which does not define that symbol.

Nothing else was touched. Which of the remaining Win32-dependent pieces —
tray icon, global hotkeys, `SetWinEventHook` — misbehave under Wine is worth
finding out empirically rather than patching blind.

## Troubleshooting

**HDT does not start at all.** Almost certainly .NET. Check that WPF is
really there:

```sh
find ~/Faugus/battlenet/drive_c/windows -iname 'PresentationFramework.dll'
```

Nothing printed means step 3 did not take.

**HDT starts but tracks nothing.** It is on a different wineserver from the
game. List everything actually running in the prefix — both Hearthstone and
HDT must appear:

```sh
. ./lib.sh && ps -o pid=,comm= -p $(prefix_pids | tr '\n' ' ')
```

(`pgrep -f` on the prefix path is unreliable here: it also matches the shell
you typed the command into. `prefix_pids` reads `WINEPREFIX` out of each
process's environment instead.)

**Overlay is in the wrong place or behind the game.** Check you are on X11:

```sh
echo "$XDG_SESSION_TYPE"    # must print: x11
```

**Logs.** HDT writes to `Logs/` inside the prefix's AppData:

```sh
ls ~/Faugus/battlenet/drive_c/users/*/AppData/Roaming/HearthstoneDeckTracker/Logs/
```

Run `./run-hdt.sh` in a terminal to see Wine's stderr, which the Faugus
launch path swallows.
