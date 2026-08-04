#!/usr/bin/env bash
# Run overlay-pin.sh automatically, as a systemd user service.
#
#   ./05-autostart-pin.sh             install, enable and start it
#   ./05-autostart-pin.sh --status    is it running, and what has it done
#   ./05-autostart-pin.sh --remove    stop, disable and delete it
#
# The service is tied to graphical-session.target, so it starts when you log in
# and stops when you log out. It inherits DISPLAY and XAUTHORITY from the
# session's systemd environment, which GNOME populates on login -- no need to
# hardcode a display number.
#
# Idle cost is one window-tree query every five seconds while HDT is not
# running. See overlay-pin.sh for why any of this is necessary.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

unit_name="hdt-overlay-pin.service"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit="$unit_dir/$unit_name"
script="$(readlink -f ./overlay-pin.sh)"

case "${1:-}" in
	--status)
		systemctl --user status "$unit_name" --no-pager || true
		exit 0
		;;
	--remove)
		systemctl --user disable --now "$unit_name" 2>/dev/null || true
		rm -f "$unit"
		systemctl --user daemon-reload
		info "Removed $unit_name."
		exit 0
		;;
	"") ;;
	*) die "Usage: $0 [--status|--remove]" ;;
esac

[ -x "$script" ] || die "overlay-pin.sh not found next to this script."

command -v systemctl >/dev/null || die "systemctl not found; this needs systemd."

mkdir -p "$unit_dir"
cat > "$unit" <<EOF
[Unit]
Description=Pin the Hearthstone Deck Tracker overlay above the game
Documentation=file://$(readlink -f ./README.md)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=$script
Restart=always
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

info "Wrote $unit"

systemctl --user daemon-reload
systemctl --user enable --now "$unit_name"

sleep 2
if systemctl --user is-active --quiet "$unit_name"; then
	info "$unit_name is running, and will start again at every login."
else
	warn "$unit_name did not stay running. Its output:"
	systemctl --user status "$unit_name" --no-pager >&2 || true
	die "Check DISPLAY is in the session environment: systemctl --user show-environment | grep DISPLAY"
fi

info "Follow what it is doing with:  journalctl --user -u $unit_name -f"
