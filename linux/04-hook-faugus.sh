#!/usr/bin/env bash
# Print the values to enter in Faugus so it starts HDT alongside Battle.net.
#
# This script deliberately does not write anything. Faugus regenerates the
# additional-application batch file from the values in its edit dialog every
# time you save a game (see write_addapp_bat in faugus/utils.py), so a
# hand-written .bat is overwritten the moment you touch the entry.
#
# Letting Faugus own that file is also the better outcome: it emits a single
# batch file that starts Battle.net and HDT one after the other in the same
# Proton session, which is precisely the shared wineserver HearthMirror needs
# in order to read Hearthstone's memory.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

require_prefix

[ -f "$HDT_DIR/$HDT_EXE_NAME" ] \
	|| die "HDT is not installed at $HDT_DIR. Run ./03-install-hdt.sh first."

# Faugus writes `start "" "z:{path}"`, and z: maps to / in the prefix, so the
# dialog wants a Linux path rather than the C:\HDT\... Windows one.
addapp="$HDT_DIR/$HDT_EXE_NAME"

# The delay is emitted as `ping -n N 127.0.0.1`, which waits about N-1
# seconds. 30 gives Battle.net a chance to bring its session up first.
delay=30

cat <<EOF

In Faugus: right-click Battle.net -> Edit, then set

  Additional application   $addapp
  Delay                    $delay
  Run first                off

and save. Enter the Linux path exactly as shown, not C:\\HDT\\...

Faugus will then generate:

  $HDT_BAT

containing:

  @echo off
  start "" "z:$HDT_PREFIX/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
  ping -n $delay 127.0.0.1 >nul
  start "" "z:$addapp"

EOF

if [ -f "$HDT_BAT" ]; then
	info "Current contents of the batch file:"
	sed 's/^/    /' "$HDT_BAT"
	echo
	warn "Saving the Faugus dialog replaces this file."
fi

cat <<'EOF'
Caveat: that batch file runs under Proton, and HDT currently does not start
under Proton on this setup (see "Known issues" in README.md). If nothing
appears after the delay, start it separately with ./run-hdt.sh, which uses
the flatpak's wine instead.
EOF
