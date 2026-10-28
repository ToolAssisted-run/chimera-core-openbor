#!/bin/bash
# run-gate.sh - the OpenBOR core's tests: the native reference (run-native)
# and the sandbox (core.wbx through run-wbx) are the same machine, on the test
# game tests/make-test-pak.py writes (a game made here, which anyone may
# have). Its probe script writes to OpenBOR's log what the game learns from
# the machine: the clock, the date, random numbers, and each key a player
# newly presses.
#
# Every test says what it compared. The tests:
#   equivalence  run-native and run-wbx: every frame's picture, the sound,
#                each step's length and lag, the clock, and every line the
#                probe wrote
#   rerecord     the sandbox saved and loaded before every frame = without
#   session      saved at a frame, a new host, loaded, finished = without
#   turbo        the first half not read back: the rest the same, and the
#                first half's pictures really not there
#   teeth        the comparison sees Start pressed one frame later
#   old pictures the same game with its pictures as GIF, PCX and BMP, the
#                formats older OpenBOR builds took (chimera#342): it loads
#                and plays to the same pictures, sound, steps and probe
#   clock        the game's clock is frames: every 60 frames a second and 200
#                of OpenBOR's ticks, the date starts at the Starting Clock
#                setting, and the computer stalling between frames changes
#                nothing
#   controls     each of the 44 controls (11 for each of four players)
#                reaches the game as that player's key
#   sound        a frame's sound is 735 samples; the punch is heard
#   picture      OpenBOR's own video settings (twice the size, a filter)
#                make the picture Chimera gets, the same in both builds
#   save data    Export Save Data is OpenBOR's Saves/ (its settings file),
#                the same in both builds and after a session; a project's
#                settings file is the game's: one that binds player 2's
#                Right to another key stops Right from reaching the game
#   refusals     a game that is not there, a file that is not a .pak, and a
#                .pak OpenBOR cannot load: each says why
#
# usage: run-gate.sh -m <miniBox checkout>
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
mb="${MINIBOX_DIR:-}"
while getopts "m:" opt; do
	case "$opt" in
		m) mb="$OPTARG" ;;
		*) exit 2 ;;
	esac
done
[ -n "$mb" ] && [ -d "$mb" ] || { echo "pass -m <miniBox checkout>" >&2; exit 2; }
mb="$(cd "$mb" && pwd)"

echo "== build (miniBox $mb)"
mkdir -p "$root/build"
step() { # step <what> <log> <command...>
	local what="$1" log="$2"; shift 2
	if ! "$@" > "$log" 2>&1; then
		grep "error:" "$log" | head -10; tail -15 "$log"; echo "$what failed ($log)"; exit 1
	fi
}
jobs="$(nproc)"
step "the native build" "$root/build/gate-native.log" make -C "$here" -f native.mk -j"$jobs" MB="$mb"
step "the guest build" "$root/build/gate-guest.log" make -C "$here" -f guest.mk -j"$jobs" MB="$mb"
native="$root/build/native/run-native"
wbx="$root/build/native/run-wbx"
core="$root/build/guest/core.wbx"

work="$root/build/gate"
rm -rf "$work"
mkdir -p "$work"
passed=0
fails=0
pass() { echo "PASS $*"; passed=$((passed + 1)); }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

python3 "$root/tests/make-test-pak.py" "$work/test.pak"

# what a run says: the digests (standard output) and the probe's lines (the
# error output, where OpenBOR's log goes)
digests() { { grep -E '^[A-Za-z]+(\[[^]]*\])?=' "$1"; grep '^probe ' "${1%.txt}.err" 2>/dev/null; } || true; }
same() { # same <test> <a.txt> <b.txt> <what>
	digests "$2" > "$2.d"
	digests "$3" > "$3.d"
	if [ -s "$2.d" ] && cmp -s "$2.d" "$3.d"; then
		pass "$1: $4"
	else
		fail "$1: $4"; diff "$2.d" "$3.d" | head -20
	fi
}
value() { grep -E "^$2=" "$1" | head -1 | sed "s/^$2=//"; }
has() { # has <test> <file> <fixed line> <what>
	if grep -qF -- "$3" "$2"; then pass "$1: $4"; else fail "$1: $4 (no line '$3')"; grep '^probe' "$2" | head -5; fi
}
hasnt() { # hasnt <test> <file> <fixed line> <what>
	if grep -qF -- "$3" "$2"; then fail "$1: $4 (found '$3')"; else pass "$1: $4"; fi
}
mkwork() { # mkwork <dir> [<settings JSON>]
	mkdir -p "$work/$1"
	cp "$work/test.pak" "$work/$1/"
	printf '{"pack":["test.pak"]}' > "$work/$1/slots"
	printf '%s' "${2:-{\}}" > "$work/$1/settings"
}

# ---------------------------------------------------------------- the game
# Start on the title, the menu, the mode, the player; the level starts near
# frame 890. Then a walk to the right (the level scrolls), a punch, a jump,
# and every control of every player in turn, four frames apart; players 2 to
# 4 press Start last (they join).
frames=1500
menus=(--press 300:P1Start:4 --press 400:P1Start:4 --press 500:P1Start:4 --press 600:P1Start:4 --press 700:P1Start:4)
play=(--press 900:P1Right:120 --press 1030:P1Attack:4 --press 1060:P1Jump:4)
controls=()
at=1100
for p in 1 2 3 4; do
	for c in Up Down Left Right Attack Attack2 Attack3 Attack4 Jump Special; do
		controls+=(--press "$at:P$p$c:2"); at=$((at + 4))
	done
done
for p in 2 3 4; do controls+=(--press "$at:P${p}Start:2"); at=$((at + 4)); done
movie=("${menus[@]}" "${play[@]}" "${controls[@]}")

mkwork game
echo "== the test game ($frames frames: the menus, the level, every control)"
"$native" "$work/game" --frames $frames "${movie[@]}" --audio "$work/n.raw" > "$work/n.txt" 2> "$work/n.err"
"$wbx" "$core" "$work/game" --frames $frames "${movie[@]}" > "$work/w.txt" 2> "$work/w.err"
same equivalence "$work/n.txt" "$work/w.txt" "native = sandbox, $frames frames: every picture, the sound, the steps, the $(grep -c '^probe' "$work/n.err") lines of the probe"
"$wbx" "$core" "$work/game" --frames $frames "${movie[@]}" --rerecord > "$work/r.txt" 2> "$work/r.err"
same rerecord "$work/r.txt" "$work/w.txt" "save+load before every frame = straight ($(sed -n 's/stateBytes=//p' "$work/r.err") state bytes)"
"$wbx" "$core" "$work/game" --frames $frames "${movie[@]}" --session-at 1000 > "$work/s.txt" 2> "$work/s.err"
same session "$work/s.txt" "$work/w.txt" "saved at frame 1000 (walking in the level), loaded into a new host = straight"

"$native" "$work/game" --frames $frames "${movie[@]}" --turbo > "$work/t.txt" 2> "$work/t.err"
digests "$work/t.txt" | grep -v '^videoHash=' > "$work/t.d"
digests "$work/n.txt" | grep -v '^videoHash=' > "$work/n.d"
if cmp -s "$work/t.d" "$work/n.d" && [ "$(value "$work/t.txt" videoHash)" != "$(value "$work/n.txt" videoHash)" ]; then
	pass "turbo: the first half not read back - the second half's pictures, the sound, the steps and the probe the same; the first half's pictures not there"
else
	fail "turbo"; diff "$work/t.d" "$work/n.d" | head
fi

late=(--press 300:P1Start:4 --press 401:P1Start:4 --press 500:P1Start:4 --press 600:P1Start:4 --press 700:P1Start:4 "${play[@]}")
"$native" "$work/game" --frames 1000 "${late[@]}" > "$work/late.txt" 2> /dev/null
"$native" "$work/game" --frames 1000 "${menus[@]}" "${play[@]}" > "$work/ontime.txt" 2> "$work/ontime.err"
if [ "$(value "$work/late.txt" videoHash)" != "$(value "$work/ontime.txt" videoHash)" ]; then
	pass "teeth: Start one frame later is another run (the comparison sees it)"
else
	fail "teeth: Start one frame later gave the same pictures"
fi

echo "== old picture formats"
mkdir -p "$work/old"
python3 "$root/tests/make-test-pak.py" --legacy-pictures "$work/old/test.pak"
printf '{"pack":["test.pak"]}' > "$work/old/slots"
printf '{}' > "$work/old/settings"
"$native" "$work/old" --frames $frames "${movie[@]}" > "$work/old.txt" 2> "$work/old.err"
same "old pictures" "$work/old.txt" "$work/n.txt" "the game with its $(strings "$work/old/test.pak" | grep -cE '^data/.*[.](gif|pcx|bmp)$') pictures as GIF, PCX and BMP plays the $frames frames to the PNG game's pictures, sound, steps and probe"

echo "== the clock"
first="$(grep -m1 '^probe n=0 ' "$work/n.err")"
second="$(grep -m1 '^probe n=60 ' "$work/n.err")"
u0="$(sed -n 's/.* unix=\([0-9]*\).*/\1/p' <<< "$first")"
u1="$(sed -n 's/.* unix=\([0-9]*\).*/\1/p' <<< "$second")"
e1="$(sed -n 's/.* elapsed=\([0-9]*\).*/\1/p' <<< "$second")"
e2="$(grep -m1 '^probe n=120 ' "$work/n.err" | sed -n 's/.* elapsed=\([0-9]*\).*/\1/p')"
if [ -n "$u0" ] && [ $((u1 - u0)) = 1 ] && [ $((e2 - e1)) = 200 ]; then
	pass "clock: 60 frames of play are a second of the date ($u0 to $u1) and 200 of OpenBOR's ticks ($e1 to $e2)"
else
	fail "clock: '$first' then '$second', elapsed $e1 then $e2"
fi
date0="$(sed -n 's/.* date=\([^ ]*\).*/\1/p' <<< "$first")"
if [ "$(date -u -d "@$u0" +%Y-%m-%dT%H:%M:%S)" = "$date0" ] && [ "$u0" -ge 946684800 ] && [ "$u0" -lt 946684860 ]; then
	pass "clock: the level starts $((u0 - 946684800)) seconds after 2000-01-01 00:00:00 (the default Starting Clock), the date the game reads ($date0, UTC)"
else
	fail "clock: unix $u0, date $date0"
fi
mkwork game2023 '{"startTime": 1700000000}'
"$native" "$work/game2023" --frames 1000 "${menus[@]}" > "$work/c2023.txt" 2> "$work/c2023.err"
u2023="$(grep -m1 '^probe n=0 ' "$work/c2023.err" | sed -n 's/.* unix=\([0-9]*\).*/\1/p')"
if [ -n "$u2023" ] && [ $((u2023 - 1700000000)) = $((u0 - 946684800)) ]; then
	pass "clock: Starting Clock 1700000000 moves the date the game reads by exactly that ($(grep -m1 '^probe n=0 ' "$work/c2023.err" | sed -n 's/.* date=\([^ ]*\).*/\1/p'))"
else
	fail "clock: Starting Clock 1700000000: unix $u2023"
fi
GATE_STALL_US=20000 "$native" "$work/game" --frames 1000 "${menus[@]}" "${play[@]}" > "$work/stall.txt" 2> "$work/stall.err"
same clock "$work/stall.txt" "$work/ontime.txt" "the computer waiting 20 ms before every frame changes nothing the game sees"

echo "== the controls"
missing=""
for p in 1 2 3 4; do
	for k in moveup movedown moveleft moveright attack attack2 attack3 attack4 jump special; do
		grep -q "^probe n=[0-9]* p$p $k\$" "$work/n.err" || missing="$missing p$p-$k"
	done
done
for p in 2 3 4; do grep -q "^probe n=[0-9]* p$p start\$" "$work/n.err" || missing="$missing p$p-start"; done
if [ -z "$missing" ]; then
	pass "controls: each of the 43 controls pressed in the level (all but player 1's Start) reached the game as that player's key"
else
	fail "controls: not seen:$missing"
fi
crossed="$(grep -c '^probe n=[0-9]* p[1-4] ' "$work/n.err")"
if [ "$crossed" = 46 ]; then
	pass "controls: and nothing else: 46 key presses seen (43, and the walk, the punch and the jump before)"
else
	fail "controls: $crossed key presses seen, not 46"; grep '^probe n=[0-9]* p[1-4] ' "$work/n.err" | head -60 | tr '\n' ' '
fi

echo "== the sound"
samples=$(($(stat -c %s "$work/n.raw") / 4))
if [ "$samples" = $((frames * 735)) ]; then
	pass "sound: $frames frames are $samples stereo samples, 735 a frame (44100 Hz at 60 frames a second)"
else
	fail "sound: $samples samples for $frames frames"
fi
peak() { # peak <raw> <first frame> <frames>: the loudest sample there
	python3 - "$1" "$2" "$3" <<'PY'
import struct, sys
path, first, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "rb") as f:
    f.seek(first * 735 * 4)
    data = f.read(n * 735 * 4)
print(max((abs(v) for v in struct.unpack("<%dh" % (len(data) // 2), data)), default=0))
PY
}
quiet="$(peak "$work/n.raw" 950 60)"
punch="$(peak "$work/n.raw" 1030 12)"
if [ "$quiet" = 0 ] && [ "$punch" -gt 1000 ]; then
	pass "sound: silence while walking (peak 0), the punch's sound when punching (peak $punch)"
else
	fail "sound: walking peak $quiet, punching peak $punch"
fi

echo "== save data"
mkdir -p "$work/sdn" "$work/sdw" "$work/sds"
"$native" "$work/game" --frames 1000 "${menus[@]}" --savedata-out "$work/sdn" > /dev/null 2>&1
"$wbx" "$core" "$work/game" --frames 1000 "${menus[@]}" --savedata-out "$work/sdw" > /dev/null 2>&1
"$wbx" "$core" "$work/game" --frames 1000 "${menus[@]}" --session-at 500 --savedata-out "$work/sds" > /dev/null 2>&1
if [ "$(cd "$work/sdn" && ls)" = "test.cfg" ] && diff -r "$work/sdn" "$work/sdw" > /dev/null && diff -r "$work/sdw" "$work/sds" > /dev/null; then
	pass "save data: Export Save Data is OpenBOR's settings file (test.cfg, $(stat -c %s "$work/sdn/test.cfg") bytes) and nothing else; native = sandbox = a session"
else
	fail "save data: export: $(cd "$work/sdn" && ls | tr '\n' ' ')"
fi
# player 2's Right is keys[1][3] of OpenBOR's settings: after ten ints and
# player 1's 13 keys, the fourth key of player 2. SDL's scancode for L (player
# 2's Right, patch 0001) is 15, for G 10. (Player 1 is no test: OpenBOR also
# gives player 1 its default keys whatever the settings say.)
python3 - "$work/sdn/test.cfg" "$work/rebound.cfg" <<'PY'
import struct, sys
data = bytearray(open(sys.argv[1], "rb").read())
offset = 10 * 4 + 13 * 4 + 3 * 4
assert struct.unpack_from("<i", data, offset)[0] == 15, "player 2's Right is not where it was expected"
struct.pack_into("<i", data, offset, 10)
open(sys.argv[2], "wb").write(data)
PY
mkdir -p "$work/seed"
cp "$work/test.pak" "$work/seed/"
cp "$work/rebound.cfg" "$work/seed/test.cfg"
printf '{"pack":["test.pak"],"savedata":["test.cfg"]}' > "$work/seed/slots"
printf '{}' > "$work/seed/settings"
"$native" "$work/seed" --frames $frames "${movie[@]}" > "$work/seed.txt" 2> "$work/seed.err"
"$wbx" "$core" "$work/seed" --frames $frames "${movie[@]}" > "$work/seedw.txt" 2> "$work/seedw.err"
if ! grep -q "^probe n=[0-9]* p2 moveright\$" "$work/seed.err" && grep -q "^probe n=[0-9]* p2 moveleft\$" "$work/seed.err" &&
   grep -q "^probe n=[0-9]* p2 moveright\$" "$work/n.err"; then
	pass "save data: a project's settings file binding player 2's Right to G is the game's: Right no longer reaches it, Left still does"
else
	fail "save data: the seeded settings: $(grep '^probe n=[0-9]* p2' "$work/seed.err" | tr '\n' ' ')"
fi
same "save data" "$work/seed.txt" "$work/seedw.txt" "the seeded settings: native = sandbox"

# OpenBOR's own video settings (its Video options menu writes them to the
# same file): the window at twice the size (hwscale, a float at byte 312)
# with its AdvanceMAME2x filter (swfilter 2, byte 272)
python3 - "$work/sdn/test.cfg" "$work/filter.cfg" <<'PY'
import struct, sys
data = bytearray(open(sys.argv[1], "rb").read())
assert len(data) == 320 and struct.unpack_from("<f", data, 312)[0] == 1.0, "the settings' layout is not the expected one"
struct.pack_into("<i", data, 272, 2)
struct.pack_into("<f", data, 312, 2.0)
open(sys.argv[2], "wb").write(data)
PY
mkdir -p "$work/filter"
cp "$work/test.pak" "$work/filter/"
cp "$work/filter.cfg" "$work/filter/test.cfg"
printf '{"pack":["test.pak"],"savedata":["test.cfg"]}' > "$work/filter/slots"
printf '{}' > "$work/filter/settings"
"$native" "$work/filter" --frames 400 --press 300:P1Start:4 --screenshot "399:$work/filter.n.tga" > "$work/filter.txt" 2> "$work/filter.err"
"$wbx" "$core" "$work/filter" --frames 400 --press 300:P1Start:4 --screenshot "399:$work/filter.w.tga" > "$work/filterw.txt" 2> "$work/filterw.err"
size="$(python3 -c "import struct,sys; print('%dx%d' % struct.unpack('<HH', open(sys.argv[1],'rb').read()[12:16]))" "$work/filter.w.tga" 2>/dev/null)"
if [ "$size" = 640x480 ] && cmp -s "$work/filter.n.tga" "$work/filter.w.tga" && [ "$(value "$work/filter.txt" videoHash)" = "$(value "$work/filterw.txt" videoHash)" ]; then
	pass "picture: OpenBOR's own settings for twice the size with its AdvanceMAME2x filter give a 640x480 picture, every frame the same in both builds"
else
	fail "picture: the filtered picture is $size; native and sandbox $(cmp -s "$work/filter.n.tga" "$work/filter.w.tga" && echo agree || echo differ)"
fi

echo "== refusals"
mkdir -p "$work/nopak"
printf '{"pack":["missing.pak"]}' > "$work/nopak/slots"; printf '{}' > "$work/nopak/settings"
"$native" "$work/nopak" --frames 1 > "$work/nopak.txt" 2> /dev/null
has refusals "$work/nopak.txt" "loadError=error.game_could_not_be_opened"$'\x1f'"missing.pak" "a game that is not there says so"
mkdir -p "$work/notpak"
head -c 4096 /dev/zero | tr '\0' 'x' > "$work/notpak/game.pak"
printf '{"pack":["game.pak"]}' > "$work/notpak/slots"; printf '{}' > "$work/notpak/settings"
"$wbx" "$core" "$work/notpak" --frames 1 > "$work/notpak.txt" 2> /dev/null
has refusals "$work/notpak.txt" "loadError=error.is_not_an_openbor_game"$'\x1f'"game.pak" "a file that is not a .pak says so (in the sandbox)"
mkdir -p "$work/nolevels"
python3 - "$root/tests/make-test-pak.py" "$work/nolevels/game.pak" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pak", sys.argv[1])
pak = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pak)
open(sys.argv[2], "wb").write(pak.pak([f for f in pak.files() if f[0] != "data/levels.txt"]))
PY
printf '{"pack":["game.pak"]}' > "$work/nolevels/slots"; printf '{}' > "$work/nolevels/settings"
"$wbx" "$core" "$work/nolevels" --frames 1 > "$work/nolevels.txt" 2> /dev/null
has refusals "$work/nolevels.txt" "loadError=error.openbor_could_not_load_because"$'\x1f'"Error loading level list from data/levels.txt" "a .pak OpenBOR cannot load is refused when it is opened, with OpenBOR's reason"

echo
echo "$passed passed, $fails failed"
[ "$fails" -eq 0 ]
