# Running Hearthstone Deck Tracker on Linux

Setup for Debian + GNOME, with Hearthstone installed through the Blizzard app
under [Faugus Launcher](https://github.com/Faugus/faugus-launcher).

Status: working. HDT builds, installs, runs in the same Proton session as
Battle.net, reads the game through HearthMirror, and shows its overlay over the
game at native resolution.

Two things are not optional, and both are explained below:

- **Hearthstone must be set to Windowed**, not fullscreen. 1920x1080 windowed
  on a 1920x1080 monitor is fine — that is the point of `overlay-pin.sh`.
- **`./overlay-pin.sh` must be running** alongside the game.

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

**You do need real .NET — because of HearthMirror, not the UI.** Wine Mono
11.2.0 runs HDT's WPF interface fine; HDT starts, renders and loads card
definitions with no Microsoft .NET present. What it cannot do is load
`HearthMirror.dll`, which is compiled from C++/CLI (`ILONLY`, but
`/clr:pure`). Mono's verifier rejects that IL:

```
System.InvalidProgramException: Invalid IL code in <Module>:
std._Variant_raw_visit1<3>._Visit<...MonoClass...MonoObject...MonoStruct...>
  modopt(System.Runtime.CompilerServices.IsImplicitlyDereferenced)
```

`<Module>`, the `std::` templates and that `modopt` are all C++/CLI compiler
output, and `MonoClass`/`MonoObject` are HearthMirror's own types for walking
Hearthstone's Mono heap. Only Microsoft's CLR executes them. Without real
.NET, HDT dies the moment it reaches for the game — which looks like "starts,
then closes instantly".

So run `./02-install-dotnet48.sh`, and note the wineserver warning below: it
must go through Proton's wine, never the flatpak's.

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

### 2. Install .NET Framework 4.8

```sh
cd linux
./01-backup-prefix.sh
./02-install-dotnet48.sh
```

Needed for HearthMirror, as explained above. Close Battle.net and Hearthstone
first — the script refuses to run otherwise. 10–20 minutes.

### 3. Install HDT into the prefix

```sh
cd linux
./03-install-hdt.sh ~/Downloads/portable-release.zip
```

Unpacks to `~/Faugus/battlenet/drive_c/HDT`, i.e. `C:\HDT` in the prefix. It
handles GitHub's nested artifact zip.

### 4. Have Faugus start HDT with Battle.net

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

### 5. Set the game windowed, and pin the overlay

In Hearthstone: **Options → Graphics → Window Mode: Windowed**. The resolution
can stay at your monitor's native one.

Then, in a terminal, for as long as you are playing:

```sh
cd linux
./overlay-pin.sh
```

Skipping either leaves the overlay stacked underneath the game. See "The
overlay and the window manager" for why.

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

The last line is expected while the game is closed.

With the game running, these confirm HearthMirror is reading its memory — the
part that needs real .NET and a shared wineserver:

```
HearthMirror RPC [client]
Helper.GetCurrentRegion >> Region: EU
GameV2.CurrentMode >> COLLECTIONMANAGER
CollectionHelper.UpdateCollection >> Updated collection!
```

And this confirms the Wine-specific overlay handling is active:

```
OverlayWindow.StartWinePolling >> Running under Wine: polling game window position and stacking every 500ms
```

Logs live at:

```
~/Faugus/battlenet/drive_c/users/steamuser/AppData/Roaming/HearthstoneDeckTracker/Logs/
```

## One Proton session per prefix

Proton locks the prefix for the whole lifetime of a session:

```python
self.prefix_lock = FileLock(self.path("pfx.lock"), timeout=-1)
```

`timeout=-1` means wait forever. A second Proton session for the same prefix
does not fail and does not warn — it blocks silently until the first exits.

The symptom is confusing: starting HDT separately while the game runs looks
like an absurdly slow launch, and then HDT appears the moment you close
Hearthstone, exactly when it is no longer useful. Nothing is broken; the
second launch was queued behind the first the whole time.

This is the reason the Faugus additional-application hook is the right design
rather than a convenience. It produces a single batch file:

```bat
@echo off
start "" "z:...\Battle.net.exe"
ping -n 30 127.0.0.1 >nul
start "" "z:...\Hearthstone Deck Tracker.exe"
```

One `umu-run`, one lock acquisition, both programs inside that one session —
which is also what puts them on a shared wineserver so HearthMirror can read
the game's memory.

`run-hdt.sh` refuses to start when anything is already running in the prefix,
rather than hanging. Use it only with the prefix idle.

## The overlay and the window manager

The overlay is a borderless window HDT keeps sized to, and stacked above, the
Hearthstone window. Both halves of that break under Wine, and both break for
the same underlying reason: Win32 reports success while X11 does something
else.

**Stacking.** "Topmost" is a Win32 concept. Wine maps `WS_EX_TOPMOST` onto the
X11 hint `_NET_WM_STATE_ABOVE`, but the window manager decides the actual
order, and Mutter raises the focused game back over the overlay every time you
click it. HDT could not tell: `SetTopmost` checked the `WS_EX_TOPMOST` style
bit, Wine still reported it as set, so nothing ever restacked. That is why the
overlay "disappeared" the moment you clicked anything.

**Position.** `HookGameWindow` learns that the game moved via
`SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE)`. Wine raises that event for
moves the *application* performs, not for moves the *window manager*
performs — so dragging Hearthstone to another monitor left the overlay behind.

`UpdatePosition` would not have helped even if the event had arrived. It opens
with

```csharp
if(hsRect.Height == 0 || (!IsContentVisible && CapturableOverlay == null))
    return;
```

and in the menus the overlay's content is collapsed, so `IsContentVisible` is
false and the call does nothing — which is exactly when you are most likely to
drag the game somewhere.

`OverlayWindow.Wine.cs` fixes both by polling every 500 ms, only when
`LinuxCompat.IsWine`. It re-issues `SetWindowPos(HWND_TOPMOST)` unconditionally,
and compares the overlay's *own* `Left`/`Top`/`Width`/`Height` against the
game's client rect rather than watching for the game to change — so drift
corrects itself whatever caused it. It calls `SetRect` directly, which carries
no visibility guard, and only layers `UpdatePosition` on top when there is
content to lay out. A mismatch is logged once per episode:

```
Overlay at 9,30 1911x1045 does not match game at 1924,33 1911x1045; repositioning
```

**Fullscreen is a third problem, and that one is not fixable from inside Wine
at all.** Confirmed on this machine:

```
Hearthstone         _NET_WM_STATE = _NET_WM_STATE_FULLSCREEN
HearthstoneOverlay  _NET_WM_STATE = _NET_WM_STATE_SKIP_PAGER,
                                    _NET_WM_STATE_SKIP_TASKBAR,
                                    _NET_WM_STATE_ABOVE
```

Wine did its part — the overlay is correctly marked ABOVE — and the game was
*still* stacked over it. Mutter puts a fullscreen window in a layer above
anything that merely asked to be ABOVE, and unredirects it as well: the screen
goes straight to the game, bypassing the compositor, and nothing can be drawn
on top. `wmctrl -b add,above` changes nothing, because the hint was already
set.

**And Wine misreports a fullscreen window's position on dual monitors.**
Measured both ways round, the client origin Wine hands out is always the *other*
monitor's origin:

| HDMI-0 (primary) at | game's X position | what HDT was told | where the overlay went |
|---|---|---|---|
| `+1920+0` | 1920 | 0 | laptop screen |
| `+0+0` | 0 | 1920 | laptop screen |

HDT's arithmetic is correct in both rows; it is being given the wrong monitor.
Rearranging the displays does not help, because the error follows the
arrangement.

### What actually works

**Windowed, at your monitor's native resolution, with `overlay-pin.sh`
running.**

```sh
./overlay-pin.sh    # leave running; Ctrl-C to stop
```

Windowed keeps Wine's coordinates honest, so the overlay lands on the right
monitor. Wine still flags a window that exactly covers the monitor as
fullscreen, but that stops mattering: `overlay-pin.sh` sets
`_NET_WM_WINDOW_TYPE_DOCK` on the overlay, which is a strictly higher Mutter
layer than a focused fullscreen window and therefore wins regardless of focus.
Keeping a non-fullscreen window on top also stops the unredirect.

It has to be a loop, and it has to run out here. Win32 has no concept of a dock
so nothing inside the prefix can ask for one, and Wine rewrites the property
back to `_NET_WM_WINDOW_TYPE_NORMAL` whenever it resyncs the window's X11 hints.

To see what the window manager is actually doing:

```sh
./overlay-doctor.sh          # stacking order, geometry, _NET_WM_STATE
./overlay-doctor.sh --fix    # add _NET_WM_STATE_ABOVE (needs `sudo apt install wmctrl`)
```

And the session must be X11: on Wayland a client may not place a window at
arbitrary screen coordinates at all, so none of this can work.

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
- **`Hearthstone Deck Tracker/Windows/OverlayWindow.Wine.cs`** (new) — polls
  the game window's position and re-asserts topmost, because under Wine the
  notifications HDT relies on for both are silently unreliable. See "The
  overlay and the window manager". Kept in its own partial-class file so it
  rebases cleanly; the only edits to existing overlay code are the two
  `Start`/`StopWinePolling` calls and the Wine branch in `SetTopmost`.
- **`Hearthstone Deck Tracker/Utility/User32.cs`** — adds `ForceTopmost`, a
  `SetWindowPos(HWND_TOPMOST)` that does not first consult the style bit.

## Troubleshooting

**Nothing launches — not even Battle.net.** Check the Faugus runner is
`GE-Proton10-34`, not `Proton-CachyOS Latest`.

**HDT starts but tracks nothing.** It is not sharing a wineserver with the
game. `pgrep -c wineserver` must print 1, and both must appear in
`prefix_pids`. Starting HDT with `--wine` guarantees this failure.

**Overlay behind the game, or left behind on the old monitor.** See "The
overlay and the window manager" above, and run `./overlay-doctor.sh`.

**`WindowsCryptographicException: Invalid data` in the log.** Wine Mono's
`ProtectedData`/DPAPI is incomplete, so HDT cannot decrypt a stored HSReplay
token and falls back to re-claiming one. Harmless as far as observed.

**Seeing Wine output.** The Faugus launch path swallows it; run
`./run-hdt.sh` from a terminal instead.

**Machine-wide lag while playing.** Check `ps -eo pid,pcpu,comm --sort=-pcpu |
head` before blaming HDT. Two things worth knowing:

- Proton starts `xalia.exe`, an accessibility bridge, and it has been measured
  burning ~55% of a core across two instances for the whole session while
  doing nothing useful. Disable it by adding `PROTON_USE_XALIA=0` to the
  Faugus entry's launch arguments (Edit → Launch arguments), alongside the
  existing `WINE_SIMULATE_WRITECOPY=1` and `PROTON_ENABLE_WAYLAND=0`. Proton
  honours the variable if it is already set.
- HDT itself sits around 45% CPU for the first minute while it processes card
  definitions, then drops off the top of the list. That part is normal.
