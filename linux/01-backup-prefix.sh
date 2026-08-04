#!/usr/bin/env bash
# Back up the parts of the Wine prefix that installing .NET can damage.
#
# Only the registry hives and drive_c/windows are saved (~325 MB here). The
# Battle.net and Hearthstone install directories are ~12 GB and winetricks
# never writes to them, so copying those would be a waste of disk.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

require_prefix

stamp="$(date +%Y-%m-%d_%H-%M-%S)"
dest="$HDT_BACKUP_DIR/$stamp"

info "Backing up prefix metadata to $dest"
mkdir -p "$dest"

for reg in system.reg user.reg userdef.reg; do
	if [ -f "$HDT_PREFIX/$reg" ]; then
		cp -a "$HDT_PREFIX/$reg" "$dest/"
	fi
done

info "Copying drive_c/windows (this takes a moment)"
tar -C "$HDT_PREFIX" -cf "$dest/windows.tar" drive_c/windows

printf '%s\n' "$HDT_PREFIX" > "$dest/PREFIX_PATH"

info "Backup complete:"
du -sh "$dest"
echo
echo "Restore with:  ./restore-prefix.sh $stamp"
