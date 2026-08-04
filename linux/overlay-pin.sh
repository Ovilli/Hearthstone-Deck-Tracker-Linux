#!/usr/bin/env bash
# Keep the overlay above a fullscreen Hearthstone, by re-typing its X11 window
# as a dock. Run it in a terminal alongside the game; Ctrl-C to stop.
#
# Only needed if you play fullscreen. Windowed at anything below your monitor's
# resolution needs none of this.
#
# Why a dock. Mutter sorts windows into stacking layers, and a *focused
# fullscreen* window lands in the same layer as a window that merely asked for
# _NET_WM_STATE_ABOVE -- which is all Wine can request on the overlay's behalf.
# Same layer means focus decides, and the game has focus, so the game wins and
# the overlay vanishes underneath it. _NET_WM_WINDOW_TYPE_DOCK is a strictly
# higher layer, so it wins regardless of focus. Keeping a non-fullscreen window
# on top also stops Mutter unredirecting the game, which would otherwise bypass
# the compositor and leave nothing able to draw over it.
#
# Why a loop. Wine owns that property and rewrites it to _NET_WM_WINDOW_TYPE_
# NORMAL whenever it resyncs the window's X11 hints, which happens on its own
# schedule. Nothing inside the prefix can ask for a dock -- Win32 has no such
# concept -- so it has to be re-applied from out here.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

command -v xprop >/dev/null || die "xprop not found. sudo apt install x11-utils"

[ "${XDG_SESSION_TYPE:-}" = "x11" ] \
	|| die "XDG_SESSION_TYPE is '${XDG_SESSION_TYPE:-unset}'. This only works on X11."

info "Pinning the overlay above fullscreen windows. Ctrl-C to stop."

last=""
while sleep 1; do
	id="$(xwininfo -root -tree 2>/dev/null \
		| grep -F '"HearthstoneOverlay"' \
		| grep -oE '0x[0-9a-f]+' | head -1)" || true

	if [ -z "$id" ]; then
		[ "$last" = "gone" ] || info "Waiting for the overlay window..."
		last="gone"
		continue
	fi

	if xprop -id "$id" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q _NET_WM_WINDOW_TYPE_DOCK; then
		[ "$last" = "$id" ] || info "Overlay $id pinned."
		last="$id"
		continue
	fi

	xprop -id "$id" -f _NET_WM_WINDOW_TYPE 32a \
		-set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_DOCK 2>/dev/null || true
	last=""
done
