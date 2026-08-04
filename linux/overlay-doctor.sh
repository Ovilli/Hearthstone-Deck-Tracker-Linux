#!/usr/bin/env bash
# Diagnose -- and work around -- the overlay ending up behind Hearthstone.
#
# Run this while Hearthstone and HDT are both up.
#
#   ./overlay-doctor.sh          report only
#   ./overlay-doctor.sh --fix    also ask the window manager to keep the
#                                overlay above everything (needs wmctrl)
#
# Background. "Topmost" is a Win32 idea. Wine translates it to the X11 hint
# _NET_WM_STATE_ABOVE, but the final stacking order is the window manager's
# call, and GNOME/Mutter raises the focused game back over the overlay every
# time you click. Wine still reports the window as topmost, so HDT has no way
# to notice from inside the prefix.
#
# Mutter also *unredirects* a genuinely fullscreen window -- it hands the
# screen straight to the game and bypasses the compositor -- and then nothing
# can be drawn over it, ABOVE hint or not. If --fix reports the overlay is now
# on top and it still is not visible, that is what you are hitting: switch
# Hearthstone to Windowed or Borderless in its own graphics options.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

fix=0
case "${1:-}" in
	--fix) fix=1 ;;
	"") ;;
	*) die "Usage: $0 [--fix]" ;;
esac

command -v xwininfo >/dev/null || die "xwininfo not found. sudo apt install x11-utils"

[ "${XDG_SESSION_TYPE:-}" = "x11" ] \
	|| warn "XDG_SESSION_TYPE is '${XDG_SESSION_TYPE:-unset}', not x11. Wayland does not
let a client place a window over another application's fullscreen window at
all. Log out and pick 'GNOME on Xorg'."

# xwininfo -root -tree lists children bottom-of-stack first, which is exactly
# the order in question. Keep that order.
tree="$(xwininfo -root -tree)"

win_id() { printf '%s\n' "$tree" | grep -F "\"$1\"" | grep -oE '^ +0x[0-9a-f]+' | tr -d ' ' | head -1; }

overlay="$(win_id HearthstoneOverlay || true)"
game="$(win_id Hearthstone || true)"

[ -n "$overlay" ] || die "No 'HearthstoneOverlay' window. Is HDT running?"
[ -n "$game" ] || die "No 'Hearthstone' window. Is the game running?"

info "Stacking order, bottom to top (only the windows that matter):"
printf '%s\n' "$tree" \
	| grep -iE 'hearthstone|deck tracker' \
	| sed 's/^ */  /'

info "Geometry"
for id in "$game" "$overlay"; do
	printf '  %s  ' "$id"
	xwininfo -id "$id" \
		| grep -E 'Absolute upper-left|Width:|Height:' \
		| tr -d ' \n' | sed 's/AbsoluteupperleftX:/x=/;s/AbsoluteupperleftY:/ y=/;s/Width:/ w=/;s/Height:/ h=/'
	printf '\n'
done

info "Window manager state"
for id in "$game" "$overlay"; do
	echo "  $id"
	xprop -id "$id" _NET_WM_STATE _NET_WM_WINDOW_TYPE 2>/dev/null | sed 's/^/    /'
done

# Position in the stack decides everything. Later in the tree listing == higher.
# grep -n numbers its *output*; the pattern still has to match the bare id.
top="$(printf '%s\n' "$tree" | grep -oE '0x[0-9a-f]+' | grep -xF -e "$overlay" -e "$game" | tail -1)"
if [ "$top" = "$game" ]; then
	warn "The game is stacked ABOVE the overlay. That is the bug."
	if xprop -id "$game" _NET_WM_STATE 2>/dev/null | grep -q _NET_WM_STATE_FULLSCREEN; then
		warn "Hearthstone holds _NET_WM_STATE_FULLSCREEN. Mutter stacks a fullscreen
window above everything that merely asked to be ABOVE, and unredirects it on top
of that, so no amount of restacking will put the overlay in front. Set the game
to Windowed in its graphics options -- windowed, not borderless: Wine requests
fullscreen for any window that exactly covers the monitor."
	fi
else
	info "The overlay is stacked above the game."
fi

[ "$fix" = 1 ] || {
	info "Re-run with --fix to ask the window manager to pin the overlay above."
	exit 0
}

command -v wmctrl >/dev/null \
	|| die "wmctrl not found, and it is what sends the request. sudo apt install wmctrl"

info "Setting _NET_WM_STATE_ABOVE on the overlay"
wmctrl -i -r "$overlay" -b add,above
sleep 1

printf '%s\n' "$(xwininfo -root -tree)" \
	| grep -iE 'hearthstone|deck tracker' \
	| sed 's/^ */  /'

info "If the overlay is now last in that list but you still cannot see it,
Hearthstone is running fullscreen and Mutter has unredirected it. Set the game
to Windowed or Borderless."
