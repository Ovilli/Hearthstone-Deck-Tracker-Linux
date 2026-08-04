#!/usr/bin/env bash
# Unpack a portable HDT build into the Battle.net Wine prefix.
#
# Usage: ./03-install-hdt.sh path/to/Hearthstone.Deck.Tracker-vX.Y.Z.zip
#
# Get that zip by running the "Build Portable (Unsigned)" workflow on your
# fork (Actions tab -> Run workflow) and downloading the `portable-release`
# artifact. WPF cannot be compiled on Linux, so the build has to happen on a
# Windows runner.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib.sh
. ./lib.sh

[ $# -ge 1 ] || die "Usage: $0 <portable-build.zip>

Download the artifact from your fork's 'Build Portable (Unsigned)' workflow
run. GitHub wraps artifacts in an outer zip; either the outer or the inner
zip works here."

src="$1"
[ -f "$src" ] || die "No such file: $src"

require_prefix

# Extraction runs on the host with python3's zipfile module rather than the
# flatpak's 7z. The flatpak sandbox has its own private /tmp and only sees
# $HOME, /mnt and /run/media, so unpacking through it would silently write
# into the sandbox and fail for any zip stored outside $HOME.
command -v python3 >/dev/null 2>&1 || die "python3 is required to unpack the build."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

info "Extracting $src"
python3 -m zipfile -e "$src" "$work/outer"

# GitHub Actions serves artifacts as a zip containing our zip. Unwrap if so.
inner="$(find "$work/outer" -maxdepth 2 -iname '*.zip' | head -1 || true)"
if [ -n "$inner" ]; then
	info "Found nested artifact zip, extracting $(basename "$inner")"
	python3 -m zipfile -e "$inner" "$work/hdt"
else
	mv "$work/outer" "$work/hdt"
fi

# The portable zip contains a single "Hearthstone Deck Tracker" directory.
payload="$(dirname "$(find "$work/hdt" -name "$HDT_EXE_NAME" -print -quit)")"
[ -n "$payload" ] && [ -d "$payload" ] \
	|| die "Could not find '$HDT_EXE_NAME' anywhere in that zip."

if [ -d "$HDT_DIR" ]; then
	warn "$HDT_DIR already exists and will be replaced."
	warn "Your decks and settings live in the prefix's AppData, not here,"
	warn "so they are not affected."
	printf 'Replace it? [y/N] '
	read -r reply
	case "$reply" in [yY]*) ;; *) die "Aborted." ;; esac
	rm -rf "$HDT_DIR"
fi

info "Installing to $HDT_DIR  ($HDT_WIN_DIR inside the prefix)"
mkdir -p "$HDT_DIR"
cp -a "$payload/." "$HDT_DIR/"

[ -f "$HDT_DIR/$HDT_EXE_NAME" ] || die "Install failed: $HDT_EXE_NAME is not in $HDT_DIR"

info "Installed:"
echo "  $HDT_DIR/$HDT_EXE_NAME"
echo
info "Next: ./04-hook-faugus.sh  (auto-start HDT with Battle.net)"
