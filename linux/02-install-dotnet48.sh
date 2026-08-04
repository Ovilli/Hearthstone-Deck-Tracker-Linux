#!/usr/bin/env bash
# Install real Microsoft .NET Framework 4.8 into the Battle.net Wine prefix.
#
# Why this is needed: the prefix currently has Wine Mono, which fakes the
# .NET registry keys but implements no WPF. HDT is a WPF application, so it
# cannot start until PresentationFramework/PresentationCore are actually
# present. Wine Mono has to come out before the Microsoft installer will run.
#
# This is the longest and most failure-prone step of the whole setup: it
# downloads ~120 MB and runs a chain of Microsoft installers under Wine.
# Expect 10-20 minutes. Run 01-backup-prefix.sh first.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

require_flatpak
require_prefix
require_prefix_idle

[ -x "$HDT_UMU" ] || die "umu-run not found at $HDT_UMU.
Launch Battle.net from Faugus once so it downloads umu-run, then retry."

if [ ! -d "$HDT_BACKUP_DIR" ]; then
	warn "No backups found in $HDT_BACKUP_DIR."
	warn "Strongly recommended: run ./01-backup-prefix.sh first."
	printf 'Continue without a backup? [y/N] '
	read -r reply
	case "$reply" in [yY]*) ;; *) die "Aborted." ;; esac
fi

# The dotnet verbs move the prefix's Windows version around (dotnet40 wants
# winxp, dotnet48 wants win7) and leave it wherever they finished. Remember
# what it was so it can be put back exactly, rather than guessed at.
original_winver="$(prefix_winver)"
info "Prefix reports Windows version: $original_winver (will restore this afterwards)"

info "Removing Wine Mono from the prefix"
in_proton_winetricks -q remove_mono || \
	warn "remove_mono returned non-zero; continuing (it may already be gone)."

info "Installing .NET Framework 4.8 (long; downloads ~120 MB)"
in_proton_winetricks -q dotnet48

info "Restoring Windows version reporting to $original_winver"
in_proton_winetricks -q "$original_winver"

info "Checking Proton can still launch programs in the prefix"
if ! timeout 120 flatpak run --command="$HDT_UMU" \
	--env=WINEPREFIX="$HDT_PREFIX" --env=GAMEID="$HDT_GAMEID" \
	--env=PROTONPATH="$HDT_PROTON" --env=PROTON_ENABLE_WAYLAND=0 \
	--env=DISPLAY="${DISPLAY:-:0}" \
	"$HDT_FLATPAK" "$HDT_PREFIX/drive_c/windows/system32/winver.exe" \
	>/dev/null 2>&1
then
	warn "winver.exe did not run cleanly under Proton."
	warn "If Battle.net also fails to start, restore the prefix:"
	warn "  ./restore-prefix.sh <timestamp>"
fi

info "Verifying WPF assemblies landed in the prefix"
found=0
for dll in PresentationFramework.dll PresentationCore.dll WindowsBase.dll; do
	if find "$HDT_PREFIX/drive_c/windows" -iname "$dll" -print -quit 2>/dev/null | grep -q .; then
		echo "  ok   $dll"
		found=$((found + 1))
	else
		echo "  MISS $dll"
	fi
done

if [ "$found" -lt 3 ]; then
	die "WPF assemblies are missing, so .NET 4.8 did not install correctly.
HDT will not start. Re-run this script, or restore the prefix with
./restore-prefix.sh and try again."
fi

info ".NET Framework 4.8 with WPF is installed. Next: ./03-install-hdt.sh"
