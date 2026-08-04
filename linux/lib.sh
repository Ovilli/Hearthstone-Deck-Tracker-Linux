# Shared configuration and helpers for the Linux setup scripts.
# Sourced by the numbered scripts in this directory; not meant to be run directly.
#
# Every value here was read off this machine's actual Faugus install. If you
# move your prefix or rename the Faugus game entry, override via the
# environment, e.g.  HDT_PREFIX=/somewhere/else ./02-install-dotnet48.sh

# --- Faugus / Proton -------------------------------------------------------

# The Wine prefix Battle.net and Hearthstone live in. HDT *must* run inside
# this same prefix: HearthMirror reads Hearthstone's Mono heap with
# ReadProcessMemory, which only works between processes sharing a wineserver.
HDT_PREFIX="${HDT_PREFIX:-$HOME/Faugus/battlenet}"

# Faugus game id, as it appears in games.json.
HDT_GAMEID="${HDT_GAMEID:-battlenet}"

# The Faugus flatpak. It bundles wine, winetricks, cabextract and 7z in
# /app/bin, so nothing has to be installed on the host.
HDT_FLATPAK="${HDT_FLATPAK:-io.github.Faugus.faugus-launcher}"

# Proton build Faugus is configured to use for this prefix. Read out of
# Faugus's own games.json rather than hardcoded, so that changing the runner
# in the Faugus UI does not silently leave these scripts launching HDT with a
# different Proton than the game. (Proton-CachyOS cannot launch anything in
# this prefix; GE-Proton10-34 works.)
_faugus_runner() {
	python3 - "$HOME/.var/app/$HDT_FLATPAK/data/faugus-launcher/games.json" "$HDT_GAMEID" <<'PY' 2>/dev/null
import json, sys
try:
    games = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
for g in games:
    if g.get("gameid") == sys.argv[2]:
        print(g.get("runner", ""))
        break
PY
}

if [ -z "${HDT_PROTON:-}" ]; then
	_runner="$(_faugus_runner)"
	[ -n "$_runner" ] || _runner="GE-Proton10-34"
	HDT_PROTON="$HOME/.local/share/Steam/compatibilitytools.d/$_runner"
fi

# umu-run, as Faugus ships it: a Python zipapp downloaded into the flatpak's
# data directory. The flatpak sets XDG_DATA_HOME to this same real host path
# rather than remapping it to ~/.local/share, so the path is identical inside
# and outside the sandbox.
HDT_UMU="${HDT_UMU:-$HOME/.var/app/$HDT_FLATPAK/data/faugus-launcher/umu-run}"

# --- HDT -------------------------------------------------------------------

# Where HDT gets installed, as a Windows path and as the matching host path.
# Deliberately kept free of spaces so the generated .bat needs no quoting
# gymnastics.
HDT_WIN_DIR="${HDT_WIN_DIR:-C:\\HDT}"
HDT_DIR="${HDT_DIR:-$HDT_PREFIX/drive_c/HDT}"
HDT_EXE_NAME="Hearthstone Deck Tracker.exe"

# The Faugus "additional application" batch file. Faugus runs this inside the
# same Proton session as Battle.net, which is exactly the launch we need.
HDT_BAT="${HDT_BAT:-$HDT_PREFIX/drive_c/Program Files (x86)/Battle.net/faugus-battlenet.bat}"

HDT_BACKUP_DIR="${HDT_BACKUP_DIR:-$HOME/Faugus/hdt-backups}"

# --- helpers ---------------------------------------------------------------

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Run winetricks against the prefix using *Proton's* wine, via umu-run.
#
# This must never be done with the flatpak's own wine. Both builds report
# "wine-11.0", but their wineserver protocol versions differ (932 for the
# flatpak, 930 for Proton-CachyOS), and touching the prefix with the wrong one
# leaves it in a state where Proton can no longer launch anything at all --
# not the game, not even winver.exe. Comparing `wine --version` strings does
# not catch this, because the strings are identical.
#
# umu-run takes `winetricks` as a positional argument and runs it with the
# Proton build named by PROTONPATH, which keeps the prefix self-consistent.
in_proton_winetricks() {
	flatpak run \
		--command="$HDT_UMU" \
		--env=WINEPREFIX="$HDT_PREFIX" \
		--env=GAMEID="$HDT_GAMEID" \
		--env=PROTONPATH="$HDT_PROTON" \
		--env=PROTON_ENABLE_WAYLAND=0 \
		--env=W_OPT_UNATTENDED=1 \
		--env=DISPLAY="${DISPLAY:-:0}" \
		"$HDT_FLATPAK" winetricks "$@"
}

# Run a command from inside the Faugus flatpak, using the flatpak's own wine.
#
# Safe only for things that do not touch the prefix (version probes and the
# like). For anything that writes to the prefix, use in_proton_winetricks --
# see the warning above.
in_flatpak() {
	local cmd="$1"; shift
	flatpak run \
		--command="$cmd" \
		--env=WINEPREFIX="$HDT_PREFIX" \
		--env=WINE=/app/bin/wine \
		--env=WINESERVER=/app/bin/wineserver \
		--env=WINEDLLOVERRIDES="mscoree=" \
		--env=W_OPT_UNATTENDED=1 \
		--env=DISPLAY="${DISPLAY:-:0}" \
		"$HDT_FLATPAK" "$@"
}

# Report the prefix's Windows version as a winetricks verb name.
#
# winetricks has no getter for this, and the dotnet verbs change the version
# behind your back (dotnet40 wants winxp, dotnet48 wants win7), so the value
# has to be captured before installing and put back afterwards. Read it out
# of the registry and map the build number onto the verb.
prefix_winver() {
	local build
	build="$(grep -a -A12 '^\[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\]' \
		"$HDT_PREFIX/system.reg" 2>/dev/null \
		| grep -a -m1 '"CurrentBuild"=' | sed 's/.*"\([0-9]*\)".*/\1/')"
	case "$build" in
		22000|2[2-9][0-9][0-9][0-9]) echo win11 ;;
		1[0-9][0-9][0-9][0-9])       echo win10 ;;
		9600)                        echo win81 ;;
		9200)                        echo win8  ;;
		7601)                        echo win7  ;;
		*)                           echo win10 ;;
	esac
}

require_prefix() {
	[ -d "$HDT_PREFIX/drive_c" ] \
		|| die "No Wine prefix at $HDT_PREFIX (expected a drive_c inside it)."
}

require_flatpak() {
	flatpak info "$HDT_FLATPAK" >/dev/null 2>&1 \
		|| die "Faugus flatpak $HDT_FLATPAK is not installed."
}

# List PIDs actually running inside the prefix.
#
# Matching on the path with `pgrep -f` is not good enough: it also matches any
# shell whose command line happens to mention the path, including the one
# calling this. Wine puts WINEPREFIX in the environment of every process it
# starts, so check that instead.
#
# The value cannot be compared literally. Faugus lays the prefix out
# Proton-style, with a `pfx -> .` symlink inside it, and Proton passes
# WINEPREFIX=<prefix>/pfx/ — trailing slash and all. So resolve both sides to
# a real path before comparing.
prefix_pids() {
	local pid want got
	want="$(readlink -f "$HDT_PREFIX")"
	for pid in /proc/[0-9]*; do
		pid="${pid#/proc/}"
		[ "$pid" = "$$" ] && continue
		# The redirect itself fails on other users' processes, and that error
		# comes from the shell rather than from tr, so the whole group has to
		# be silenced.
		got="$({ tr '\0' '\n' < "/proc/$pid/environ"; } 2>/dev/null \
			| grep -m1 '^WINEPREFIX=' | cut -d= -f2-)"
		[ -n "$got" ] || continue
		[ "$(readlink -f "$got")" = "$want" ] && echo "$pid"
	done
}

# winetricks and wineboot rewrite the prefix. Refuse to touch it while
# anything is still running in there.
require_prefix_idle() {
	local pids
	pids="$(prefix_pids)"
	if [ -n "$pids" ]; then
		warn "Processes still running in $HDT_PREFIX:"
		# shellcheck disable=SC2086
		ps -o pid=,comm= -p $(echo "$pids" | tr '\n' ' ') >&2 || true
		die "Close Battle.net and Hearthstone (and let wineserver exit) first."
	fi
}
