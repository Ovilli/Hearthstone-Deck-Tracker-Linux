#!/usr/bin/env bash
# Start HDT by hand inside the Battle.net prefix.
#
# Usage: ./run-hdt.sh            # umu-run/Proton — the only one that can track
#        ./run-hdt.sh --wine     # flatpak wine — diagnostics only, cannot track
#
# The routine way to run HDT is via Faugus, which starts it alongside
# Battle.net (see 04-hook-faugus.sh). Use this script to start it separately,
# or to see the Wine output that the Faugus launch path swallows.
#
#   proton  umu-run with Proton-CachyOS, exactly what Faugus uses for
#           Battle.net. This is the only usable option: HearthMirror reads
#           Hearthstone's memory with ReadProcessMemory, and that requires
#           both processes to share a wineserver.
#
#   wine    The flatpak's wine. It will start HDT only while no Proton session
#           is running, and it can never share a wineserver with one --
#           attempting it fails with
#
#               wine client error:0: version mismatch 932/930
#
#           Both builds call themselves wine-11.0, but their wineserver
#           protocol versions differ. So HDT started this way cannot see
#           Hearthstone. Useful for checking that HDT itself runs; useless for
#           actually tracking a game.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

launcher="proton"
case "${1:-}" in
	--wine) launcher="wine" ;;
	--proton|"") ;;
	*) die "Usage: $0 [--proton|--wine]" ;;
esac

if [ "$launcher" = "wine" ]; then
	warn "The flatpak's wine cannot share a wineserver with Proton, so HDT"
	warn "started this way will not see Hearthstone. Diagnostics only."
fi

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
