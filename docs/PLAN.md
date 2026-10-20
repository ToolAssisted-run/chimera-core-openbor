# The OpenBOR core: the design log

What was decided, why, and what was measured. Newest last.

## Build an OpenBOR core (user-decided, 2026-10-20)

Chimera issue #325 asked for OpenBOR. OpenBOR is BSD-3-Clause, a C program
on SDL 2 with its own software renderer and mixer: the shape of the game
cores Chimera already has (SDLPoP, rawgl). The owner decided to build it,
in a repository of its own, and to be asked again before it is published.

## The shape

- **The frame.** OpenBOR owns its loops: the menus, a level and a cutscene
  each loop on their own and draw by presenting through SDL. The engine runs
  on a stack of its own (`coroutine.c`), and every `SDL_RenderPresent` ends a
  frame: the core reads the picture back and switches to the caller. The
  next FrameAdvance switches in again. Nothing is threaded.
- **The clock** counts microseconds from power-on and moves where the
  engine waits (SDL_Delay, usleep, nanosleep) and at each frame's end: frame
  k ends at (k + 1) / 60 s. A wait past a frame's end ends the frame there
  without a picture (a lag frame). OpenBOR's logic runs at 200 steps a
  second from that clock.
- **Spinning.** OpenBOR's fades wait by reading the clock over and over and
  never wait or draw: on a clock that only moves when the game waits, that
  loop never ends (it hung the first level start). A loop that reads the
  clock, or asks for events, 4096 times without the clock moving or a
  picture being drawn ends the frame there, as a wait past its end would.
  Counted calls, so the same in every run.
- **Input** is the keyboard: each control presses the key OpenBOR's default
  setup has for it. Upstream gives players 2 to 4 no keys at all (its
  defines for them name joysticks, and `clearbuttons` sets them to none);
  patch 0001 gives them keys, so the core can press them. Player 1 always
  also has OpenBOR's default keys, whatever its settings say.
- **Sound** is pulled: at each frame's end OpenBOR's mixer (the callback it
  gave SDL) runs for that frame's samples, 735 at 44100 Hz. OpenBOR asks SDL
  for 48000 Hz 24-bit first and falls back to 44100 16-bit, which is the
  only one the core's device takes.
- **Loading.** Init runs the engine until OpenBOR has loaded the game
  (patch 0002 calls the core after `startup()`), then to the end of that
  frame. A game that cannot load is refused when it is opened, with
  OpenBOR's own reason (patch 0002 also hands the core what `borShutdown`
  says). The loading screens are frames before the movie's first; at most
  18000 of them (five minutes of the machine's time).
- **Files.** The .pak is read where Chimera mounted it. Saves/ is in the
  core's memory (written files are memory streams) and travels in
  savestates; Export Save Data writes it out, and a project's save files are
  put back before the game starts. Logs/ goes to the error output (the core
  log). ScreenShots/ is refused. Nothing of the computer's own (/proc, /sys,
  /dev) is opened.
- **Everything else the game could observe**: the date is the Starting
  Clock setting plus the machine's time, in UTC (localtime, localtime_r,
  mktime and ctime are wrapped too: natively they read the computer's time
  zone); the computer's memory (`sysinfo`) is the same figure everywhere;
  `mallinfo2` (glibc's, named in an out-of-memory message) says nothing;
  `__DATE__`, shown in OpenBOR's log and menus, is the pinned commit's date
  and not the build's. OpenBOR's random numbers start from a fixed seed.

## The test game

No published OpenBOR game may be put on a CI runner, and none was offered
yet. `tests/make-test-pak.py` makes one: every picture and sound is drawn
by the script. Its update script is the probe (docs/BUILDING.md). Two
things a real game has that it needed: a font's first cell must not be empty
(it carries the palette for every character), and a level with nothing left
to spawn and no enemy ends at once, so the later boxes spawn as the screen
scrolls to them.

## Measured (2026-10-20)

- Native reference = sandbox on 1500 frames of the test game (the menus, a
  level, every control of every player): every picture, the sound, every
  step's length and lag, the clock and the 57 lines of the probe.
- Savestate before every frame: 2,764,944 bytes, the run the same as
  without. Saved at frame 1000, loaded into a new host: the same.
- Speed: 1500 frames in 1.18 s in the sandbox on an Intel Core Ultra 7
  265KF (about 1270 frames a second), 34 MB of the computer's memory.
- core.wbx is 3.5 MB.

Not tried: any published OpenBOR game; WebM cutscenes (not built: OpenBOR's
WebM player needs libvpx and threads).
