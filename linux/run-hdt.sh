#!/usr/bin/env bash
# Start HDT by hand inside the Battle.net prefix.
#
# Usage: ./run-hdt.sh            # flatpak wine (verified to start HDT)
#        ./run-hdt.sh --proton   # umu-run/Proton (see the caveat below)
#
# The routine way to run HDT is 04-hook-faugus.sh, which has Faugus start it
# together with Battle.net. Use this script to start it separately, or to see
# the Wine output that the Faugus launch path swallows.
#
# Two launchers, because they fail in opposite directions:
#
#   wine    The flatpak's plain wine-11.0 — the same build that installed
#           .NET into the prefix. HDT starts and runs correctly under it.
#
#   proton  umu-run with Proton-CachyOS, reproducing exactly what Faugus uses
#           for Battle.net. Architecturally this is what you want, because
#           HearthMirror reads Hearthstone's memory with ReadProcessMemory and
#           that only works between processes on a shared wineserver. But on
#           this setup HDT never reaches its first line under Proton: the
#           process does not appear and no log is written. Root cause not yet
#           identified; .NET itself survives the attempt intact.
#
# So neither option is proven end-to-end yet. `wine` gets you a running
# tracker; whether it shares a wineserver with a Proton-launched Hearthstone,
# and therefore whether it actually tracks, still has to be confirmed with the
# game running. See "Verifying tracking" in README.md.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

launcher="wine"
case "${1:-}" in
	--proton) launcher="proton" ;;
	--wine|"") ;;
	*) die "Usage: $0 [--wine|--proton]" ;;
esac

require_flatpak
require_prefix

[ -f "$HDT_DIR/$HDT_EXE_NAME" ] \
	|| die "HDT is not installed at $HDT_DIR. Run ./03-install-hdt.sh first."

if [ -z "$(prefix_pids)" ]; then
	warn "Nothing is running in the prefix yet. For tracking to work, start"
	warn "Battle.net and Hearthstone from Faugus first, so that HDT attaches"
	warn "to a running game."
fi

info "Launching $HDT_DIR/$HDT_EXE_NAME via $launcher"

if [ "$launcher" = "proton" ]; then
	[ -x "$HDT_UMU" ] || die "umu-run not found at $HDT_UMU.
Launch Battle.net from Faugus once so it downloads umu-run, then retry."

	# umu-run resolves its target on the Linux filesystem, so it needs the
	# Unix path. (The Faugus .bat from 04-hook-faugus.sh uses the Windows
	# path instead, because cmd.exe interprets that one.)
	#
	# PROTON_ENABLE_WAYLAND=0 keeps everything on XWayland, matching the
	# launch arguments already set on the Faugus battlenet entry. The overlay
	# positions itself over the Hearthstone window using X11 coordinates,
	# which native Wayland does not permit.
	exec flatpak run \
		--command="$HDT_UMU" \
		--env=WINEPREFIX="$HDT_PREFIX" \
		--env=GAMEID="$HDT_GAMEID" \
		--env=PROTONPATH="$HDT_PROTON" \
		--env=PROTON_ENABLE_WAYLAND=0 \
		--env=WINE_SIMULATE_WRITECOPY=1 \
		--env=DISPLAY="${DISPLAY:-:0}" \
		"$HDT_FLATPAK" \
		"$HDT_DIR/$HDT_EXE_NAME"
fi

# Note the absence of WINEDLLOVERRIDES here. lib.sh's in_flatpak sets
# mscoree= to keep winetricks from prompting about Mono during installation;
# carrying that over to a launch would disable the .NET runtime and stop HDT
# from starting at all.
exec flatpak run \
	--command=wine \
	--env=WINEPREFIX="$HDT_PREFIX" \
	--env=DISPLAY="${DISPLAY:-:0}" \
	"$HDT_FLATPAK" \
	"$HDT_WIN_DIR\\$HDT_EXE_NAME"
