#!/bin/bash
# The frontend half of the tests: the package, as Chimera loads it, playing
# the test game tests/make-test-pak.py writes - so it needs no game of
# anyone's and runs anywhere.
#
# - chimera-run (the engine, no window): a movie from a file and the same
#   movie in a hand-written project. The last picture must be the native
#   reference's (run-native) at that frame.
# - Chimera's window, run headless (no display needed): the same project
#   opened and played through Lua, its last picture compared with the
#   reference's; and the package's bindings becoming Chimera's defaults.
#
# Nothing is written under the Chimera checkout: the window's settings, its
# cache and recovery files, the Base path and the sandbox's log are all in
# build/frontend.
#
# Usage: tests/run-frontend.sh --chimera-root <chimera checkout> [-m <miniBox dir>]
# Needs: the native reference built (make -f waterbox/native.mk), and
# Chimera built (its window and chimera-run).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
wb="$root/waterbox"
chimera_root=""
mb="${MINIBOX_DIR:-}"
while [ $# -gt 0 ]; do
	case "$1" in
		--chimera-root) chimera_root="$2"; shift ;;
		-m) mb="$2"; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done
[ -n "$chimera_root" ] && [ -d "$chimera_root" ] || { echo "say where Chimera is: --chimera-root <chimera checkout>" >&2; exit 2; }
chimera_root="$(cd "$chimera_root" && pwd)"
[ -n "$mb" ] || mb="$chimera_root/extern/chimera-common-minibox"

chimera_exe="$chimera_root/build/meson-linux/source/ui/chimera"
crun="$chimera_root/build/meson-linux/chimera-run"
rn="$root/build/native/run-native"
work="$root/build/frontend"
rm -rf "$work"
mkdir -p "$work/data" "$work/native"
game="$work/test.pak"
python3 "$here/make-test-pak.py" "$game"

ok=0
failed=0
skipped=0
report() {
	printf "%-22s %-6s %s\n" "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok+1)) ;; SKIP) skipped=$((skipped+1)) ;; *) failed=$((failed+1)) ;; esac
}
printf "%-22s %-6s %s\n" "Check" "Result" "Detail"
printf "%-22s %-6s %s\n" "-----" "------" "------"

[ -x "$rn" ] || { echo "the native reference is not built: $rn (make -C waterbox -f native.mk)" >&2; exit 1; }

# ---------------------------------------------------------------- the package
if bash "$wb/build-package.sh" -m "$mb" -o "$work/pkg" > "$work/package.log" 2>&1; then
	report "package" PASS "$(grep 'package sha1' "$work/package.log")"
else
	report "package" FAIL "see build/frontend/package.log"; echo; echo "$ok ok, $failed failed"; exit 1
fi
pkg="$work/pkg/openbor.chimeraCore"

# The movie: Start through the title, the menu, the mode and the player
# (frames 300 to 700); in the level, Right walks from 900 for 120 frames and
# Attack punches at 1030. The last frame is 1049, the punch's.
frames=1050
cp "$game" "$work/native/"
printf '{"pack":["%s"]}' "$(basename "$game")" > "$work/native/slots"
printf '{}' > "$work/native/settings"
"$rn" "$work/native" --frames "$frames" --press 300:P1Start:4 --press 400:P1Start:4 --press 500:P1Start:4 --press 600:P1Start:4 \
	--press 700:P1Start:4 --press 900:P1Right:120 --press 1030:P1Attack:4 \
	--screenshot "$((frames - 1)):$work/native.last.tga" > "$work/native.txt" 2> "$work/native.err"
mkdir -p "$work/proj"
cp "$game" "$work/proj/"
python3 "$here/make-project.py" "$pkg" "$work/proj/test.chimeraProject" "$frames" \
	"press=P1 Start:300:4" "press=P1 Start:400:4" "press=P1 Start:500:4" "press=P1 Start:600:4" "press=P1 Start:700:4" \
	"press=P1 Right:900:120" "press=P1 Attack:1030:4" log="$work/test.log" \
	-- "pack=$work/proj/$(basename "$game")"

# ---------------------------------------------------------------- chimera-run
if [ ! -x "$crun" ]; then
	report "engine" SKIP "no chimera-run at $crun"
else
	# a game runs only in a project (Chimera, 2026-10-26): the game and the movie
	# made into one by chimera-run
	( cd "$work" && "$crun" --new-project "$work/movie.chimeraProject" "$pkg" "$game" test.log > "$work/movie.make.log" 2>&1 \
		&& timeout 900 "$crun" --project "$work/movie.chimeraProject" "$pkg" --files "$(dirname "$game")" --frames "$frames" \
		--screenshot "$((frames - 1))=$work/run.last.tga" --meta "$work/run.meta" > "$work/run.log" 2>&1 )
	if grep -q '^status=OK' "$work/run.meta" 2>/dev/null &&
	   python3 "$here/compare-pictures.py" "$work/native.last.tga" "$work/run.last.tga" > "$work/run.pic" 2>&1; then
		report "engine:movie" PASS "$frames frames from a movie made into a project (the menus, the level, a walk and a punch): the last picture is the reference's, $(cat "$work/run.pic")"
	else
		report "engine:movie" FAIL "$(grep -m1 detail= "$work/run.meta" 2>/dev/null) $(cat "$work/run.pic" 2>/dev/null) (build/frontend/run.log)"
	fi

	( cd "$work" && timeout 900 "$crun" --project "$work/proj/test.chimeraProject" "$pkg" --files "$work/proj" --frames "$frames" \
		--screenshot "$((frames - 1))=$work/proj.last.tga" --meta "$work/proj.meta" > "$work/proj.log" 2>&1 )
	if grep -q '^status=OK' "$work/proj.meta" 2>/dev/null &&
	   python3 "$here/compare-pictures.py" "$work/native.last.tga" "$work/proj.last.tga" > "$work/proj.pic" 2>&1; then
		report "engine:project" PASS "the same movie in a project, the .pak in its slot: the same last picture"
	else
		report "engine:project" FAIL "$(grep -m1 detail= "$work/proj.meta" 2>/dev/null) $(cat "$work/proj.pic" 2>/dev/null) (build/frontend/proj.log)"
	fi
fi

# ---------------------------------------------------------------- Chimera itself
if [ ! -x "$chimera_exe" ]; then
	report "window" SKIP "Chimera's window is not built ($chimera_exe)"
	echo; echo "$ok ok, $failed failed, $skipped skipped"; [ "$failed" -eq 0 ]; exit
fi
# the window run headless: the cores installed in the checkout, its settings,
# cache and recovery files the run's own, and nothing carried over from a
# Chimera installed on this machine
export ALSOFT_DRIVERS=null CHIMERA_CORES_DIR="$chimera_root/build/Cores" CHIMERA_QT_CACHE="$work/qt-cache" CHIMERA_QT_RECOVERY="$work/qt-recovery" \
	CHIMERA_QT_HASHES="$work/qt-file-hashes.txt" CHIMERA_QT_CHIMERA_SETTINGS="$work/no-chimera-config.ini"
export MINIBOX_LOG="$work/minibox.log"

# settings of its own, with the Base path (and so every folder Chimera
# writes by default) in the work dir
config="$work/settings.json"
python3 -c 'import json, sys; json.dump({"paths.base": sys.argv[2]}, open(sys.argv[1], "w"), indent=2)' "$config" "$work"

gui() {
	# gui <tag> <config> <project> <frames>
	local tag="$1" cfg="$2" project="$3" nframes="$4"
	mkdir -p "$work/$tag"
	printf 'frames=%s\nmeta=%s\nshot=%s\n' "$nframes" "$work/$tag/meta.txt" "$work/$tag/last.png" > "$work/$tag/job.txt"
	( cd "$work" && MINIHAWK_JOB="$work/$tag/job.txt" timeout 900 "$chimera_exe" --headless "--config=$cfg" \
		"--core=$pkg" "--project=$project" "--lua=$here/frontend.lua" ) > "$work/$tag.log" 2>&1
}
meta() { sed -n "s/^$2=//p" "$work/$1/meta.txt" 2>/dev/null; }

# the movie's last frame is shown after frame 299 has run: the window has
# advanced 300 frames
gui gui "$config" "$work/proj/test.chimeraProject" "$frames"
if [ "$(meta gui status)" = "OK" ] && python3 "$here/compare-pictures.py" "$work/native.last.tga" "$work/gui/last.png" > "$work/gui.pic" 2>&1; then
	report "window:project" PASS "the project opened in Chimera: after $(meta gui frames) frames, $(meta gui width)x$(meta gui height), the picture is the reference's"
else
	report "window:project" FAIL "status $(meta gui status) $(meta gui detail); $(cat "$work/gui.pic" 2>/dev/null) (build/frontend/gui.log)"
fi

# the bindings the package ships are the machine's when nobody changed them
# (the window keeps only the keys a person changed; fresh settings have none)
mkdir -p "$work/keys"
printf 'out=%s/keys/controls.json\nmeta=%s/keys/meta.txt\n' "$work" "$work" > "$work/keys/job.txt"
( cd "$work" && MINIHAWK_JOB="$work/keys/job.txt" timeout 900 "$chimera_exe" --headless "--config=$work/settings.keys.json" \
	"--core=$pkg" "--project=$work/proj/test.chimeraProject" "--lua=$here/dump-controls.lua" ) > "$work/keys.log" 2>&1
if grep -q "^status=OK" "$work/keys/meta.txt" 2>/dev/null && python3 "$here/check-keybinds.py" "$work/keys/controls.json" "$wb/default_keybinds.json" "OpenBOR" "P1 Start" > "$work/keys.txt" 2>&1; then
	report "window:keybinds" PASS "$(cat "$work/keys.txt")"
else
	report "window:keybinds" FAIL "$(head -1 "$work/keys.txt" 2>/dev/null) (build/frontend/keys.log)"
fi

echo
echo "$ok ok, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
