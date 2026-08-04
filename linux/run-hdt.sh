#!/usr/bin/env bash
# Start HDT by hand inside the Battle.net Proton prefix.
#
# The normal path is 04-hook-faugus.sh, which has Faugus start HDT together
# with Battle.net. This script is for starting it separately, or for seeing
# the Wine output when something goes wrong.
#
# Launching through umu-run (rather than plain wine) matters: it reproduces
# the Proton environment Faugus uses, so HDT ends up on the same wineserver
# as Hearthstone. A different wineserver means HearthMirror cannot read
# Hearthstone's memory and the tracker sees nothing.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

require_flatpak
require_prefix

[ -f "$HDT_DIR/$HDT_EXE_NAME" ] \
	|| die "HDT is not installed at $HDT_DIR. Run ./03-install-hdt.sh first."

if [ -z "$(prefix_pids)" ]; then
	warn "Nothing is running in the prefix yet. HDT works best when started"
	warn "after Battle.net, so start the game from Faugus first if you want"
	warn "the overlay and deck tracking to attach immediately."
fi

info "Launching $HDT_WIN_DIR\\$HDT_EXE_NAME"

# PROTON_ENABLE_WAYLAND=0 keeps everything on XWayland, matching the launch
# arguments already set on the Faugus battlenet entry. The overlay positions
# itself over the Hearthstone window using X11 window coordinates, which
# native Wayland does not permit.
exec flatpak run \
	--command="$HDT_UMU_SANDBOX_PATH" \
	--env=WINEPREFIX="$HDT_PREFIX" \
	--env=GAMEID="$HDT_GAMEID" \
	--env=PROTONPATH="$HDT_PROTON" \
	--env=PROTON_ENABLE_WAYLAND=0 \
	--env=WINE_SIMULATE_WRITECOPY=1 \
	--env=DISPLAY="${DISPLAY:-:0}" \
	"$HDT_FLATPAK" \
	"$HDT_WIN_DIR\\$HDT_EXE_NAME"
