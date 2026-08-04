# Running Hearthstone Deck Tracker on Linux

Setup for Debian + GNOME, with Hearthstone installed through the Blizzard app
under [Faugus Launcher](https://github.com/Faugus/faugus-launcher).

Status: HDT builds, installs, and runs in the same Proton session as
Battle.net. Tracking a live game is the one thing still to be confirmed.

## How this works, and why

HDT is a WPF application targeting .NET Framework 4.7.2. WPF has no Linux
implementation, so there is no native Linux build to make. It does not need
one: Hearthstone only runs under Wine/Proton anyway, and HDT works when it
runs inside **the same Wine prefix, in the same Proton session** as the game.

That constraint drives everything here. HearthMirror reads Hearthstone's Mono
heap with `ReadProcessMemory`, and the overlay tracks the game window with
`FindWindow`/`GetWindowRect`. Both only work between processes sharing a
wineserver. Start HDT any other way and it runs, sees nothing, and tracks
nothing.

So: one prefix, one Proton session, two Windows programs. Faugus's
"additional application" feature does exactly that, which is the whole setup.

## Requirements

| | |
|---|---|
| Prefix | `~/Faugus/battlenet` |
| Runner | **GE-Proton10-34** — see below |
| Session | **X11** |
| Hearthstone | `C:\Program Files (x86)\Hearthstone` |

**The runner matters.** With `Proton-CachyOS Latest` nothing in the prefix
launches — not HDT, not Battle.net, not `winver.exe`. Switching the Faugus
runner to `GE-Proton10-34` fixes it. If things mysteriously fail to start,
check the runner first.

**The session must be X11.** GNOME on Wayland does not let a client place a
window at arbitrary coordinates or keep it above another application's
fullscreen window, which is what the overlay does. The Faugus entry already
sets `PROTON_ENABLE_WAYLAND=0`; also pick "GNOME on Xorg" at the login screen.

**You do not need to install .NET.** The Wine Mono that ships with Proton
(wine-mono 11.2.0) implements enough WPF to run HDT. Verified with no
Microsoft .NET in the prefix at all — HDT reported
`.NET Framework: 533320` and rendered its full UI. `02-install-dotnet48.sh`
exists but should not be run; see the note in its header.

`Config.cs` already defaults `HearthstoneDirectory` to
`C:\Program Files (x86)\Hearthstone`, so no path configuration is needed.

## Setup

### 1. Build HDT

WPF cannot be compiled on Linux, so the build runs on a Windows CI runner.

On your fork: **Actions → Build Portable (Unsigned) → Run workflow**. When it
finishes, download the `portable-release` artifact.

That workflow is `.github/workflows/build-linux-portable.yml`, a copy of
upstream's `build-portable.yml` with the DigiCert signing and VSTest steps
removed (they need secrets a fork does not have) and the deprecated
`::set-output` calls replaced.

### 2. Install HDT into the prefix

```sh
cd linux
./03-install-hdt.sh ~/Downloads/portable-release.zip
```

Unpacks to `~/Faugus/battlenet/drive_c/HDT`, i.e. `C:\HDT` in the prefix. It
handles GitHub's nested artifact zip.

### 3. Have Faugus start HDT with Battle.net

```sh
./04-hook-faugus.sh
```

That prints the values to enter. In Faugus, right-click Battle.net → Edit:

| Field | Value |
|---|---|
| Additional application | `/home/ovilli/Faugus/battlenet/drive_c/HDT/Hearthstone Deck Tracker.exe` |
| Delay | `30` |
| Run first | off |

A **Linux** path, not `C:\HDT\...`: Faugus writes `start "" "z:{path}"` and
`z:` maps to `/`. The delay becomes `ping -n N 127.0.0.1`, roughly N−1
seconds. Faugus regenerates the batch file itself on save, which is why
`04-hook-faugus.sh` only prints values instead of writing one.

Launching Battle.net from Faugus then starts both, in one Proton session.

To start HDT by hand instead:

```sh
./run-hdt.sh            # umu-run/Proton — the only mode that can track
./run-hdt.sh --wine     # flatpak wine — diagnostics only, cannot track
```

## Verifying tracking

HDT *running* and HDT *tracking* are different things.

Confirmed working: Battle.net and HDT both up, sharing one wineserver.

```sh
. ./lib.sh && ps -o pid=,comm= -p $(prefix_pids | tr '\n' ' ') | grep -iE 'hearth|agent'
pgrep -c wineserver     # must print 1
```

HDT's log confirms a healthy start:

```
HDT: 1.54.4.1, Operating System: Microsoft Windows 11 19045, .NET Framework: 533320
CardDefsManager >> Loaded initial base CardDefs: Count=35320
LogWatcherManager.Start >> Using Hearthstone log directory 'C:\Program Files (x86)\Hearthstone\Logs'
OverlayWindow.SetTopmost >> Hearthstone window not found
```

The last line is expected while the game is closed. **Still to confirm:**
launch Hearthstone, get into a match, and check that line stops appearing and
that cards actually track. That exercises HearthMirror's memory reads and the
overlay, neither of which has been observed working yet.

Logs live at:

```
~/Faugus/battlenet/drive_c/users/steamuser/AppData/Roaming/HearthstoneDeckTracker/Logs/
```

## The wineserver protocol trap

**Never run winetricks against this prefix with the flatpak's wine.** Doing so
breaks it for Proton: afterwards Proton launches nothing in it. The prefix
looks fine on disk — registry format and prefix version unchanged. It just
stops working.

The two Wine builds are not interchangeable:

```
wine client error:0: version mismatch 932/930
```

The flatpak's wine speaks wineserver protocol **932**, Proton-CachyOS **930**.
Both report `wine-11.0`, so comparing `wine --version` output does not detect
the mismatch at all.

Consequences:

- Anything that writes to the prefix must go through `in_proton_winetricks`
  in `lib.sh`, which drives winetricks via `umu-run` and Proton's own wine.
  `in_flatpak` is for read-only probes.
- `./run-hdt.sh --wine` can never track. It starts HDT only when no Proton
  session is running and cannot attach to Proton's wineserver, so it never
  sees Hearthstone.
- `01-backup-prefix.sh` / `restore-prefix.sh` exist for when this bites. Note
  the backup covers only `drive_c/windows` and the registry hives — enough to
  undo a winetricks run, not a general-purpose prefix backup.

## Source changes in this fork

Deliberately minimal, to stay easy to rebase on upstream.

- **`Hearthstone Deck Tracker/Utility/LinuxCompat.cs`** (new) — detects Wine
  by probing `ntdll` for the `wine_get_version` export.
- **`Hearthstone Deck Tracker/Utility/Updating/Updater.Default.cs`** — the
  updater is disabled under Wine. It checks *upstream* HearthSim releases, so
  on a fork build it would offer to replace your build with an upstream one,
  and `HDTUpdate.exe` swapping files underneath a running Wine process
  corrupts the install. The check sits at the top of `CheckForUpdates`, ahead
  of the `force` parameter, because `Core.Initialize` passes `force: true` and
  would otherwise skip a guard placed in `ShouldCheckForUpdates`. The Squirrel
  updater needs no change: it is behind `#if(SQUIRREL)`, which the `Release`
  configuration used for the portable build does not define.

## Troubleshooting

**Nothing launches — not even Battle.net.** Check the Faugus runner is
`GE-Proton10-34`, not `Proton-CachyOS Latest`.

**HDT starts but tracks nothing.** It is not sharing a wineserver with the
game. `pgrep -c wineserver` must print 1, and both must appear in
`prefix_pids`. Starting HDT with `--wine` guarantees this failure.

**Overlay in the wrong place or behind the game.** `echo $XDG_SESSION_TYPE`
must print `x11`.

**`WindowsCryptographicException: Invalid data` in the log.** Wine Mono's
`ProtectedData`/DPAPI is incomplete, so HDT cannot decrypt a stored HSReplay
token and falls back to re-claiming one. Harmless as far as observed.

**Seeing Wine output.** The Faugus launch path swallows it; run
`./run-hdt.sh` from a terminal instead.
