#!/usr/bin/env bash
# Roll the prefix back to a snapshot taken by 01-backup-prefix.sh.
#
# Usage: ./restore-prefix.sh <timestamp>
#        ./restore-prefix.sh            # lists available snapshots
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

if [ $# -lt 1 ]; then
	info "Available snapshots in $HDT_BACKUP_DIR:"
	ls -1 "$HDT_BACKUP_DIR" 2>/dev/null || echo "  (none)"
	exit 0
fi

src="$HDT_BACKUP_DIR/$1"
[ -d "$src" ] || die "No snapshot at $src"

require_prefix
require_prefix_idle

warn "This overwrites the registry hives and drive_c/windows in:"
warn "  $HDT_PREFIX"
warn "with the snapshot from $1. Anything installed into the prefix since"
warn "that snapshot will stop working."
printf 'Type "restore" to continue: '
read -r reply
[ "$reply" = "restore" ] || die "Aborted."

for reg in system.reg user.reg userdef.reg; do
	[ -f "$src/$reg" ] && cp -a "$src/$reg" "$HDT_PREFIX/"
done

info "Restoring drive_c/windows"
rm -rf "$HDT_PREFIX/drive_c/windows"
tar -C "$HDT_PREFIX" -xf "$src/windows.tar"

info "Restored $HDT_PREFIX from snapshot $1"
