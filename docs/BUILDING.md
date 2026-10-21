# Building and testing the OpenBOR core

## Requirements

- Linux on x86-64, with GCC (the guest kit's compiler is the system's, over
  miniBox's sysroot), make, Python 3, git, binutils.
- A Chimera checkout beside this one, with miniBox built: its host library
  and C guest toolchain (`meson-linux`), and its C++ toolchain (`meson-cpp`),
  whose build of musl's math the native reference links:

      mb=<chimera>/extern/chimera-common-minibox
      meson setup "$mb/build/meson-linux" "$mb" && meson compile -C "$mb/build/meson-linux"
      meson setup "$mb/build/meson-cpp" "$mb" -Dguest_cpp=true && meson compile -C "$mb/build/meson-cpp"

- For the frontend test: Chimera built (its `chimera-run` and its window,
  `dotnet build source/gui/Chimera.sln -c Release`), mono and Xvfb.

## Sources

    git clone --recursive https://github.com/ToolAssisted-run/chimera-core-openbor

`extern/openbor` is OpenBOR at commit 65a7f0b (build 8027, 2026-10-18).
The build applies `patches/` to it in place; `waterbox/apply-patches.sh`
leaves a tree that already has the whole series alone and refuses one that
has part of it. `waterbox/compat/version.h` stands in for the `version.h`
OpenBOR's own build writes from git, and says which commit it is.

## The steps

From `waterbox/`, with `MB=<chimera>/extern/chimera-common-minibox`:

1. `make -f native.mk -j$(nproc) MB=$MB`: `build/native/run-native`, the
   native reference (OpenBOR, SDL and the libraries compiled for this
   computer, with the sandbox's own math functions, made by
   `make-native-libm.sh`), and `build/native/run-wbx`, which runs a
   `core.wbx` in the sandbox. About ten seconds on 16 threads.
2. `make -f guest.mk -j$(nproc) MB=$MB`: `build/guest/core.wbx`, checked by
   miniBox's `check-wbx.sh`.
3. `./build-package.sh -m $MB` (or `-r <chimera>` to install it in that
   checkout's `build/Cores`): `openbor.chimeraCore`. It does step 2 itself.

## The tests

- `waterbox/run-gate.sh -m <mb>`: builds both, then the core's tests on the
  test game (native against sandbox, savestates, turbo, the clock, every
  control, the sound, the picture with OpenBOR's filters, save data, the
  refusals). Each test says what it compared. About 30 seconds.
- `tests/run-frontend.sh --chimera-root <chimera>`: the package through
  `chimera-run` and through Chimera's window.
- Chimera's contract tests, against the package's folder:

      CHIMERA_CORES_DIR=<folder> dotnet test \
        <chimera>/source/gui/Chimera.Tests.Client.Common/Chimera.Tests.Client.Common.csproj \
        -c Release --filter "FullyQualifiedName~InstalledCorePackagesTests|FullyQualifiedName~MnemonicUniquenessTests"

The runners take a work folder holding what Chimera would mount: the .pak,
a `slots` file (`{"pack":["test.pak"]}`, with `"savedata":[...]` for save
files) and a `settings` file. A movie for them is `--press AT:TOKENS:LEN`
or a file of lines naming what is held each frame (`--movie`); the names
are waterbox.config's without spaces (`P1Start`, `P2Attack2`, `Escape`).

OpenBOR's log goes to the error output: run-native shows it, and in Chimera
it is the core's log.

## The test game

`tests/make-test-pak.py <out.pak>` writes it: a block figure that walks,
punches and jumps, boxes, one level that scrolls, the menu screens, three
fonts and a few tones, all drawn and made by the script, so anyone may have
it. Its `data/scripts/update.c` is the probe: it writes to OpenBOR's log
every 60th pass the game's clock, the date and a random number, and every
key a player newly presses.

## Troubleshooting

- The native reference hangs before its first frame and its log shows
  nothing after the RAM figures: OpenBOR did not find the .pak and fell into
  its pak chooser. The game's name comes from the `slots` file in the work
  folder.
- A crash drawing a font: a font picture whose first cell is empty has no
  palette (OpenBOR takes every character's from the first).
- "OpenBOR could not load the game: ...": the reason is OpenBOR's own, from
  its shutdown (patch 0002).
- "Unable to load image file '....gif'" on an older game: upstream reads PNG
  only since 2026-06-01; patch 0003 brings back GIF, PCX and BMP pictures
  (docs/PLAN.md, chimera#342).
