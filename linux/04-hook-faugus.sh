#!/usr/bin/env bash
# Make Faugus start HDT alongside Battle.net.
#
# Faugus already has an "additional application" hook for the battlenet entry
# pointing at faugus-battlenet.bat, and that file is empty. Filling it in is
# the cleanest way to launch HDT: Faugus runs the batch file inside the very
# same Proton session as Battle.net, which is exactly what HearthMirror needs
# in order to read Hearthstone's memory.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

require_prefix

[ -f "$HDT_DIR/$HDT_EXE_NAME" ] \
	|| die "HDT is not installed at $HDT_DIR. Run ./03-install-hdt.sh first."

games_json="$HOME/.var/app/$HDT_FLATPAK/data/faugus-launcher/games.json"

if [ -f "$HDT_BAT" ] && [ -s "$HDT_BAT" ]; then
	warn "$HDT_BAT is not empty. Current contents:"
	sed 's/^/    /' "$HDT_BAT" >&2
	printf 'Overwrite it? [y/N] '
	read -r reply
	case "$reply" in [yY]*) ;; *) die "Aborted." ;; esac
fi

info "Writing $HDT_BAT"
mkdir -p "$(dirname "$HDT_BAT")"
# CRLF line endings: this is parsed by Wine's cmd.exe.
printf '@echo off\r\nstart "" "%s\\%s"\r\n' "$HDT_WIN_DIR" "$HDT_EXE_NAME" > "$HDT_BAT"

echo
info "Batch file written. One manual step is left, because editing"
info "games.json while Faugus is running would just be overwritten:"
echo
echo "  1. Open Faugus Launcher"
echo "  2. Right-click the Battle.net entry -> Edit"
echo "  3. Enable the additional-application option, confirm it points at:"
echo "       $HDT_BAT"
echo "  4. Save"
echo
echo "Faugus stores this in:"
echo "  $games_json"
echo "as the \"addapp_enabled\" field on the \"$HDT_GAMEID\" entry, which is"
echo "currently empty. \"addapp_bat\" is already set correctly."
echo
info "You can also start HDT by hand at any time with ./run-hdt.sh"
