# chimera-core-openbor

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, that plays games made with
**[OpenBOR](https://github.com/DCurrent/openbor)**, the open-source engine
for 2D beat 'em ups (the continuation of Beats of Rage). It is OpenBOR's own
engine, built for Chimera's sandbox, and produces one file,
`openbor.chimeraCore`, that goes in Chimera's `cores` folder.

## Status

Published: each push to `main` that passes the tests publishes a `dev`
release, and a dated nightly is made once a day when `main` moved. Chimera's
Core Manager lists it.

- OpenBOR at its current development version (build 8027), with its own
  software renderer and mixer: the picture is what OpenBOR draws, the sound
  what it mixes, one frame at a time.
- Tried: this repository's test game (a small game made by
  `tests/make-test-pak.py`). The sandboxed core and a plain native build
  agree on every picture, the sound and everything the game's script saw;
  savestates land where the straight run does. No published OpenBOR game
  has been tried yet.
- Not there: WebM video (OpenBOR's WebM player needs libvpx and threads,
  which this build leaves out: a game's WebM cutscenes do not play) and
  OpenGL (OpenBOR draws in software, as its SDL port does without OpenGL).

## What you bring

The game's `.pak` file: an OpenBOR game is its `data` folder packed into
one `.pak`.

## Buttons and settings

- **Four players**, each with OpenBOR's eleven controls: Up, Down, Left,
  Right, Attack, Attack 2 to 4, Jump, Special and Start. Each presses the
  key OpenBOR's default setup has for it. Start pauses; **Escape** goes back
  in OpenBOR's menus.
- **Starting Clock**: the date the game reads when it starts (a game's
  scripts can read it). Movies need the same value.
- **OpenBOR's own options** apply as in OpenBOR: its Video options can
  double the window and pick one of its filters (Bilinear, AdvanceMAME2x,
  Scanlines and others), and the picture Chimera gets is the filtered one.

OpenBOR's save files (its settings, progress and high scores) live in the
core's memory and are carried by savestates. Emulator > Export Save Data
writes them out, and a project's "Save data" slot puts them back before the
game starts.

## Building and testing

[docs/BUILDING.md](docs/BUILDING.md) has every step. [docs/PLAN.md](docs/PLAN.md)
is the design log: what was decided, why, and what was measured.

## Licence

This repository's own code is MIT. OpenBOR is BSD-3-Clause; SDL 2 and zlib
are under the zlib licence, libpng under its own (version 2), libogg and
libvorbis BSD-3-Clause. The package carries every licence text. See
[LICENSE](LICENSE).
