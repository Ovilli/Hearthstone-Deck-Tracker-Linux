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

# The flatpak's wine and the Proton build must be the same Wine version,
# otherwise winetricks' wineboot will migrate the prefix out from under
# Proton. On this machine both are wine-11.0.
flatpak_wine="$(in_flatpak wine --version 2>/dev/null | tail -1 || true)"
proton_wine="$("$HDT_PROTON/files/bin/wine" --version 2>/dev/null | tail -1 || true)"
info "flatpak wine: ${flatpak_wine:-unknown}"
info "Proton wine:  ${proton_wine:-unknown}"

flatpak_major="$(printf '%s' "$flatpak_wine" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
proton_major="$(printf '%s' "$proton_wine" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"

if [ -z "$flatpak_major" ] || [ -z "$proton_major" ]; then
	warn "Could not determine both Wine versions. Continuing, but if the"
	warn "prefix misbehaves afterwards, restore it with ./restore-prefix.sh"
elif [ "$flatpak_major" != "$proton_major" ]; then
	die "Wine version mismatch: flatpak $flatpak_major vs Proton $proton_major.
Running winetricks would migrate the prefix and likely break Proton's use of
it. Update the Faugus flatpak or switch the Faugus runner so both match."
fi

if [ ! -d "$HDT_BACKUP_DIR" ]; then
	warn "No backups found in $HDT_BACKUP_DIR."
	warn "Strongly recommended: run ./01-backup-prefix.sh first."
	printf 'Continue without a backup? [y/N] '
	read -r reply
	case "$reply" in [yY]*) ;; *) die "Aborted." ;; esac
fi

info "Removing Wine Mono from the prefix"
in_flatpak winetricks -q remove_mono || \
	warn "remove_mono returned non-zero; continuing (it may already be gone)."

info "Installing .NET Framework 4.8 (long; downloads ~120 MB)"
in_flatpak winetricks -q dotnet48

# The dotnet48 verb leaves the prefix reporting Windows 7. Battle.net and
# Hearthstone both expect Windows 10.
info "Restoring Windows 10 version reporting"
in_flatpak winetricks -q win10

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
