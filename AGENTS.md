# AGENTS.md - chimera-core-openbor

OpenBOR (the 2D beat 'em up engine) as a Chimera core: OpenBOR's SDL port,
SDL 2 and the libraries it uses, built for miniBox's sandbox and driven a
frame at a time. The user brings a game's `.pak`. Read Chimera's
`docs/new-core.md` and this repository's `docs/PLAN.md` first.

## Layout

- `extern/` - submodules, each at a pinned commit: `openbor`, `SDL` (2.32),
  `zlib`, `libpng`, `ogg`, `vorbis`. The build applies `patches/` to
  `extern/openbor` in place (`waterbox/apply-patches.sh`, which checks the
  whole series).
- `patches/` - numbered patches to OpenBOR.
- `waterbox/` - the core: `openbor-driver.c` (the machine: the frame, the
  clock, the keys, the sound, Saves/), `seams.c` (every call of OpenBOR's
  and SDL's the core answers, by the linker's `--wrap`), `wbx-entry.c` (the
  exports), `coroutine.c` (the game's own stack); the makefiles
  (`sources.mk`, `native.mk`, `guest.mk`); the package's declarations
  (`waterbox.config`, `file_slots.json`, `default_keybinds.json`,
  `package-licenses.json`); the harness (`gate-harness.h`, `run-native.c`,
  `run-wbx.c`, `input-names.h`) and `run-gate.sh`.
- `tests/` - `make-test-pak.py` (the test game), `run-frontend.sh` and its
  helpers.
- `build/` - every output. Ignored by git.

## Commands

    mb=<chimera>/extern/chimera-common-minibox
    make -C waterbox -f native.mk -j$(nproc) MB=$mb   # the native reference
    make -C waterbox -f guest.mk -j$(nproc) MB=$mb    # core.wbx
    waterbox/run-gate.sh -m $mb                       # the core's tests
    waterbox/build-package.sh -r <chimera>            # the package, installed
    tests/run-frontend.sh --chimera-root <chimera>    # through Chimera

## Rules

- Everything the game can observe comes from the core: no host clock, no
  host file, no environment, no time zone. A new call OpenBOR makes to the
  outside gets an answer in `seams.c` that is the same in both builds, and
  its name in `sources.mk`'s WRAPS.
- A wrap that the harness also calls (fopen, chdir, mkdir, opendir, getenv,
  exit) passes the harness's calls through: `bordrv_on_game_stack()` tells
  the game's from the harness's.
- The native reference links the sandbox's math (`make-native-libm.sh`).
- A change to `waterbox.config`'s buttons changes `openbor-driver.c`'s
  `k_keys`, `openbor-driver.h` and `input-names.h` the same way, in the same
  order.
- Every new test is broken on purpose once and seen to fail.
- Write in plain language; prose is ASCII. Commits: `type(scope): what
  changed`, body with how it was tested, Chimera's trailers.
- Stop a run by its PID, never with `pkill -f`.
