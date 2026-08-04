#!/usr/bin/env bash
# Install real Microsoft .NET Framework 4.8 into the Battle.net Wine prefix.
#
# Required -- but not for the reason first assumed here. Wine Mono 11.2.0
# runs HDT's WPF UI perfectly well; the UI is not the problem. HearthMirror
# is. HearthMirror.dll is compiled from C++/CLI (ILONLY, but /clr:pure), and
# Mono cannot JIT that flavour of IL. Loading it produces
#
#   System.InvalidProgramException: Invalid IL code in <Module>:
#   std._Variant_raw_visit1<3>._Visit<...MonoClass...MonoObject...>
#
# and kills HDT the moment it reaches for the game's memory. Only Microsoft's
# CLR executes those C++/CLI constructs, so real .NET has to be in the prefix
# for tracking to work at all.
#
# The install drives winetricks through umu-run and Proton's own wine. Never
# use the flatpak's wine for this: see "The wineserver protocol trap" in
# README.md.
#
# Expect 10-20 minutes and a ~120 MB download. Run 01-backup-prefix.sh first.
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

# umu-run refuses to reapply a verb it believes is already present, and it
# decides that by reading $WINEPREFIX/winetricks.log (umu_util.py, "winetricks
# verb '...' is already installed"). It checks before winetricks ever runs, so
# passing --force through does not help.
#
# That log lives at the prefix root, which restore-prefix.sh does not touch --
# it reverts drive_c/windows and the registry hives, both elsewhere. So after
# a failed install followed by a restore, the log still claims dotnet48 while
# the prefix contains none of it, and the install can never be retried.
#
# Drop the stale lines when the files they claim are demonstrably absent. The
# prefix is the authority, not the log.
if [ -f "$HDT_PREFIX/winetricks.log" ] \
	&& grep -qx "dotnet48" "$HDT_PREFIX/winetricks.log" \
	&& ! find "$HDT_PREFIX/drive_c/windows" -iname clr.dll -print -quit 2>/dev/null | grep -q .
then
	warn "winetricks.log claims dotnet48 is installed, but clr.dll is absent."
	warn "Clearing the stale entries so the install can proceed."
	cp -a "$HDT_PREFIX/winetricks.log" "$HDT_PREFIX/winetricks.log.bak"
	grep -vxE "dotnet4[08]" "$HDT_PREFIX/winetricks.log.bak" > "$HDT_PREFIX/winetricks.log"
fi

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
