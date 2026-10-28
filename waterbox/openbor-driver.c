/* openbor-driver.c - OpenBOR as a Chimera machine.
 *
 * OpenBOR's engine owns its main loop: menus, levels and cutscenes each loop
 * on their own, and every pass ends by drawing the screen. A core is called a
 * frame at a time, so the engine runs on a stack of its own (coroutine.c) and
 * each time it presents a picture it switches back to FrameAdvance; the next
 * FrameAdvance switches in again. Nothing is threaded.
 *
 * The clock counts microseconds from power-on and moves only where the
 * engine waits (usleep, SDL_Delay, the frame limiter's loop) and at the end
 * of each frame: frame k ends at (k + 1) / 60 s. A wait that runs past the end
 * of a frame without a picture being drawn ends that frame without one (a lag
 * frame) and goes on in the next, so a loop that only waits still moves at 60
 * frames a second. A loop that waits by reading the clock over and over, or
 * by asking for events that never come (OpenBOR's fades do the first), would
 * wait forever on a clock that moves only when it waits: after 4096 such
 * reads with nothing drawn, the frame ends there, as a wait past its end
 * would. OpenBOR's game logic runs at its own 200 steps a second from that
 * clock (timer_getinterval), the same steps for the same frames.
 *
 * Input is a keyboard: each control is the key OpenBOR's default setup has
 * for it (player 1's are upstream's; players 2 to 4, whose defaults upstream
 * are joysticks, get keys by patch 0001). Keys that change become SDL key
 * events, and the keyboard state OpenBOR reads is the core's.
 *
 * Sound is pulled: at the end of each frame OpenBOR's mixer (the callback it
 * gave SDL) is run for exactly that frame's samples, 735 at 44100 Hz.
 *
 * The picture is what OpenBOR's renderer drew, read back when it presents.
 *
 * Files: the game's .pak is read where Chimera mounted it. OpenBOR's saves
 * (Saves/) live in the core's memory and are carried by savestates; its log
 * goes to the error output; screenshots are refused.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#include <SDL.h>

#include <emulibc.h>
#include <waterbox_settings.h>
#include <waterbox_slots.h>

#include "coroutine.h"
#include "openbor-driver.h"

/* A text a person reads is a key of languages/en.json, each of its
 * arguments after a TEXT_ARG (chimera docs/translations.md). TEXT_ARG is a
 * string of its own so the byte after it is never read as more of its hex. */
#define TEXT_ARG "\x1f"

FILE *__real_fopen(const char *path, const char *mode);
int openbor_sdl_main(int argc, char *argv[]);

/* ------------------------------------------------------------------ state */

#define MAX_SAVES 32

struct save_file
{
	char name[128];       /* under Saves/ */
	char *data;
	size_t size;
	int exists;
};

static struct
{
	void *host_sp, *game_sp;
	int on_game;          /* running on the game's stack */
	int over;             /* the game ended (exit) */
	int exit_code;
	int started;          /* OpenBOR has loaded the game (patch 0002) */
	char stopped[1024];   /* why OpenBOR stopped, as it said it */
	char pack[512];       /* where the .pak is mounted */

	uint64_t now;         /* microseconds since power-on */
	uint64_t frames;      /* frames ended */
	int64_t start_time;   /* the calendar at power-on (Starting Clock) */
	int spins;            /* clock reads and empty event polls since it moved */
	int pictured;         /* this frame drew a picture */
	int input_read;
	int render;

	uint8_t keyboard[SDL_NUM_SCANCODES];
	uint8_t buttons[BOR_BTN_COUNT];

	uint32_t picture[BOR_MAX_W * BOR_MAX_H];
	int width, height;

	SDL_AudioCallback audio_cb;
	void *audio_user;
	int audio_open, audio_paused;
	uint64_t samples;     /* samples mixed since power-on */
	int16_t audio[2 * BOR_AUDIO_RATE];
	int audio_frames;

	struct save_file saves[MAX_SAVES];
	int nsaves;
	char message[1024];   /* the last message box OpenBOR showed */
} g;

/* the keys of the controls (patch 0001 gives players 2 to 4 theirs) */
static const SDL_Scancode k_keys[BOR_BTN_COUNT] = {
	/* player 1: OpenBOR's own defaults */
	SDL_SCANCODE_UP, SDL_SCANCODE_DOWN, SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT,
	SDL_SCANCODE_A, SDL_SCANCODE_S, SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_D, SDL_SCANCODE_F,
	SDL_SCANCODE_RETURN,
	/* player 2 */
	SDL_SCANCODE_I, SDL_SCANCODE_K, SDL_SCANCODE_J, SDL_SCANCODE_L,
	SDL_SCANCODE_Q, SDL_SCANCODE_W, SDL_SCANCODE_E, SDL_SCANCODE_R, SDL_SCANCODE_T, SDL_SCANCODE_Y,
	SDL_SCANCODE_U,
	/* player 3 */
	SDL_SCANCODE_KP_8, SDL_SCANCODE_KP_2, SDL_SCANCODE_KP_4, SDL_SCANCODE_KP_6,
	SDL_SCANCODE_KP_7, SDL_SCANCODE_KP_9, SDL_SCANCODE_KP_1, SDL_SCANCODE_KP_3, SDL_SCANCODE_KP_0, SDL_SCANCODE_KP_PERIOD,
	SDL_SCANCODE_KP_ENTER,
	/* player 4 */
	SDL_SCANCODE_1, SDL_SCANCODE_2, SDL_SCANCODE_3, SDL_SCANCODE_4,
	SDL_SCANCODE_5, SDL_SCANCODE_6, SDL_SCANCODE_7, SDL_SCANCODE_8, SDL_SCANCODE_9, SDL_SCANCODE_0,
	SDL_SCANCODE_MINUS,
	/* Escape: OpenBOR's menu and pause */
	SDL_SCANCODE_ESCAPE,
};

/* ------------------------------------------------------------------ clock */

static uint64_t frame_end(uint64_t k) { return (k + 1) * 1000000ull / BOR_FPS; }

static void spin(void);

uint64_t bordrv_now_us(void)
{
	spin();
	return g.now;
}

int64_t bordrv_unix_time(void)
{
	spin();
	return g.start_time + (int64_t)(g.now / 1000000ull);
}

int bordrv_on_game_stack(void) { return g.on_game; }

/* the sound of the time between the last frame's end and now */
static void run_audio(void)
{
	const uint64_t total = g.now * BOR_AUDIO_RATE / 1000000ull;
	int n = (int)(total - g.samples);
	if (n < 0) n = 0;
	if (n > BOR_AUDIO_RATE) n = BOR_AUDIO_RATE;
	memset(g.audio, 0, (size_t)n * 4);
	if (g.audio_open && !g.audio_paused && g.audio_cb)
	{
		/* in 1024-sample blocks, as SDL's device would ask */
		for (int done = 0; done < n;)
		{
			int len = n - done < 1024 ? n - done : 1024;
			g.audio_cb(g.audio_user, (Uint8 *)(g.audio + done * 2), len * 4);
			done += len;
		}
	}
	g.samples = total;
	g.audio_frames = n;
}

/* The end of a frame: its sound, then back to FrameAdvance. */
static void end_frame(void)
{
	uint64_t end = frame_end(g.frames);
	if (g.now < end) g.now = end;
	run_audio();
	g.frames++;
	g.spins = 0;
	g.on_game = 0;
	chimera_co_switch(&g.game_sp, g.host_sp);
}

void bordrv_delay_us(uint64_t us)
{
	if (!g.on_game) return;
	uint64_t target = g.now + us;
	/* a wait past the end of the frame ends it, without a picture */
	while (target > frame_end(g.frames))
	{
		g.now = frame_end(g.frames);
		end_frame();
	}
	g.now = target;
	g.spins = 0;
}

/* A loop that keeps reading the clock or asking for events, without the
 * clock moving or a picture being drawn, waits for something only time
 * brings. After 4096 such asks the frame ends there (without a picture), as
 * a wait past it would. 1 when it ended. */
static int spun_out(void)
{
	if (!g.on_game || g.over || ++g.spins < 4096) return 0;
	g.now = frame_end(g.frames);
	end_frame();
	return 1;
}

static void spin(void) { (void)spun_out(); }

int bordrv_idle_pump(void) { return spun_out(); }

/* ---------------------------------------------------------------- picture */

void bordrv_present(void *renderer)
{
	if (!g.on_game) return;
	SDL_Renderer *r = (SDL_Renderer *)renderer;
	int w = 0, h = 0;
	if (r && SDL_GetRendererOutputSize(r, &w, &h) == 0 && w > 0 && h > 0 && w <= BOR_MAX_W && h <= BOR_MAX_H)
	{
		if (g.render)
			SDL_RenderReadPixels(r, NULL, SDL_PIXELFORMAT_ARGB8888, g.picture, w * 4);
		g.width = w;
		g.height = h;
		g.pictured = 1;
	}
	end_frame();
}

/* ------------------------------------------------------------------- input */

const uint8_t *bordrv_keyboard_state(void)
{
	g.input_read = 1;
	return g.keyboard;
}

void bordrv_set_button(int index, int on)
{
	if (index >= 0 && index < BOR_BTN_COUNT) g.buttons[index] = on ? 1 : 0;
}

/* the keys that changed, as events, and the state OpenBOR reads */
static void send_keys(void)
{
	for (int i = 0; i < BOR_BTN_COUNT; i++)
	{
		const SDL_Scancode sc = k_keys[i];
		const int want = g.buttons[i];
		if (g.keyboard[sc] == want) continue;
		g.keyboard[sc] = (uint8_t)want;
		SDL_Event ev;
		memset(&ev, 0, sizeof ev);
		ev.type = want ? SDL_KEYDOWN : SDL_KEYUP;
		ev.key.state = want ? SDL_PRESSED : SDL_RELEASED;
		ev.key.keysym.scancode = sc;
		ev.key.keysym.sym = SDL_GetKeyFromScancode(sc);
		SDL_PushEvent(&ev);
	}
}

/* ------------------------------------------------------------------- sound */

void bordrv_audio_open(void *callback, void *userdata)
{
	g.audio_cb = (SDL_AudioCallback)callback;
	g.audio_user = userdata;
	g.audio_open = 1;
	g.audio_paused = 1;
}

void bordrv_audio_close(void) { g.audio_open = 0; }

void bordrv_audio_pause(int paused) { g.audio_paused = paused; }

/* ------------------------------------------------------------------- files */

/* OpenBOR's log: what is written goes to the error output (Chimera's core
 * log), and nothing is kept to read back */
static ssize_t log_write(void *c, const char *buf, size_t size)
{
	(void)c;
	return (ssize_t)fwrite(buf, 1, size, stderr);
}

static struct save_file *find_save(const char *name, int create)
{
	for (int i = 0; i < g.nsaves; i++)
		if (!strcmp(g.saves[i].name, name)) return &g.saves[i];
	if (!create || g.nsaves == MAX_SAVES || strlen(name) >= sizeof g.saves[0].name) return NULL;
	struct save_file *s = &g.saves[g.nsaves++];
	memset(s, 0, sizeof *s);
	strcpy(s->name, name);
	return s;
}

/* where OpenBOR's own folders are, after any "./" */
static const char *under(const char *path, const char *dir)
{
	while (path[0] == '.' && path[1] == '/') path += 2;
	size_t n = strlen(dir);
	return strncmp(path, dir, n) == 0 && path[n] == '/' ? path + n + 1 : NULL;
}

FILE *bordrv_fopen(const char *path, const char *mode, int *handled)
{
	*handled = 0;
	const char *rest;
	if ((rest = under(path, "Logs")) != NULL)
	{
		*handled = 1;
		if (strchr(mode, 'r') && !strchr(mode, '+')) { errno = ENOENT; return NULL; }
		cookie_io_functions_t io = { NULL, log_write, NULL, NULL };
		return fopencookie(NULL, mode, io);
	}
	if (under(path, "ScreenShots") != NULL)
	{
		*handled = 1;
		errno = EACCES;
		return NULL;
	}
	if ((rest = under(path, "Saves")) != NULL)
	{
		*handled = 1;
		const int write = strchr(mode, 'w') != NULL || strchr(mode, 'a') != NULL;
		struct save_file *s = find_save(rest, write);
		if (!s) { errno = write ? ENOSPC : ENOENT; return NULL; }
		if (write)
		{
			if (strchr(mode, 'a') || strchr(mode, '+')) { errno = EINVAL; return NULL; }
			free(s->data);
			s->data = NULL;
			s->size = 0;
			s->exists = 1;
			return open_memstream(&s->data, &s->size);
		}
		if (!s->exists || !s->size) { errno = ENOENT; return NULL; }
		return fmemopen(s->data, s->size, "r");
	}
	return NULL;
}

int32_t bordrv_saves_count(void)
{
	int n = 0;
	for (int i = 0; i < g.nsaves; i++)
		if (g.saves[i].exists && g.saves[i].size) n++;
	return n;
}

static struct save_file *nth_save(int32_t k)
{
	for (int i = 0; i < g.nsaves; i++)
		if (g.saves[i].exists && g.saves[i].size && k-- == 0) return &g.saves[i];
	return NULL;
}

const char *bordrv_saves_name(int32_t i) { struct save_file *s = nth_save(i); return s ? s->name : ""; }
int64_t bordrv_saves_size(int32_t i) { struct save_file *s = nth_save(i); return s ? (int64_t)s->size : 0; }
const uint8_t *bordrv_saves_data(int32_t i) { struct save_file *s = nth_save(i); return s ? (const uint8_t *)s->data : NULL; }

/* a project's save file, read into the core's memory before the game starts */
static int seed_save(const char *mounted)
{
	FILE *f = __real_fopen(mounted, "rb");
	if (!f) return 0;
	const char *base = strrchr(mounted, '/');
	base = base ? base + 1 : mounted;
	struct save_file *s = find_save(base, 1);
	if (!s) { fclose(f); return 0; }
	FILE *m = open_memstream(&s->data, &s->size);
	int c;
	while ((c = fgetc(f)) != EOF) fputc(c, m);
	fclose(f);
	fclose(m);
	s->exists = 1;
	return 1;
}

/* ------------------------------------------------------------ the game ends */

void bordrv_message(const char *title, const char *text)
{
	snprintf(g.message, sizeof g.message, "%s%s%s", title ? title : "", title && *title ? ": " : "", text ? text : "");
	fprintf(stderr, "[openbor] %s\n", g.message);
}

/* patch 0002: startup() has loaded the game */
void chimera_bor_started(void) { g.started = 1; }

/* patch 0002: OpenBOR stops, saying why (status 0 is the player quitting) */
void chimera_bor_shutdown(int status, const char *msg, va_list arguments)
{
	if (!status || !msg) return;
	vsnprintf(g.stopped, sizeof g.stopped, msg, arguments);
	/* one line, without OpenBOR's line ends */
	for (char *c = g.stopped; *c; c++)
		if (*c == '\n' || *c == '\r') *c = ' ';
	for (size_t n = strlen(g.stopped); n && g.stopped[n - 1] == ' ';)
		g.stopped[--n] = 0;
}

void bordrv_game_exit(int code)
{
	g.over = 1;
	g.exit_code = code;
	for (;;)
	{
		/* the machine stays: every frame from here is a frame with no new
		 * picture and silence, as a finished program's screen would be */
		run_audio();
		g.frames++;
		g.on_game = 0;
		chimera_co_switch(&g.game_sp, g.host_sp);
		g.now = frame_end(g.frames - 1);
	}
}

void chimera_co_entry(void)
{
	char *argv[] = { "OpenBOR", g.pack, NULL };
	openbor_sdl_main(2, argv);
	bordrv_game_exit(0);
}

/* ------------------------------------------------------------ Chimera's calls */

int bordrv_init(char *err, int errsz)
{
	err[0] = 0;
	char value[64];
	g.start_time = 946684800; /* 2000-01-01 */
	if (wbx_setting_str("startTime", value, sizeof value) > 0)
		g.start_time = strtoll(value, NULL, 10);

	/* the game: the project's "pack" slot, or a file opened without a project
	 * (mounted as "game", its name in rom.name) */
	if (wbx_slot_count("pack") > 0)
		wbx_slot_name("pack", 0, g.pack, sizeof g.pack);
	else
	{
		FILE *f = __real_fopen("rom.name", "rb");
		if (f)
		{
			size_t n = fread(g.pack, 1, sizeof g.pack - 1, f);
			g.pack[n] = 0;
			fclose(f);
		}
		if (!g.pack[0]) snprintf(g.pack, sizeof g.pack, "game");
	}
	FILE *pf = __real_fopen(g.pack, "rb");
	if (!pf)
	{
		snprintf(err, (size_t)errsz, "error.game_could_not_be_opened" TEXT_ARG "%s", g.pack);
		return 0;
	}
	char magic[4] = { 0 };
	const size_t got = fread(magic, 1, sizeof magic, pf);
	fclose(pf);
	if (got != sizeof magic || memcmp(magic, "PACK", 4) != 0)
	{
		snprintf(err, (size_t)errsz, "error.is_not_an_openbor_game" TEXT_ARG "%s", g.pack);
		return 0;
	}

	/* the project's save data, where OpenBOR keeps it */
	for (int i = 0; i < wbx_slot_count("savedata"); i++)
	{
		char name[512];
		if (wbx_slot_name("savedata", i, name, sizeof name) && !seed_save(name))
		{
			snprintf(err, (size_t)errsz, "error.save_data_file_could_not_be_read" TEXT_ARG "%s", name);
			return 0;
		}
	}

	/* The game starts on its own stack and runs until OpenBOR has loaded
	 * it (its loading screens are frames before the movie's first), then to
	 * the end of that frame: a game that cannot load is refused here. */
	g.render = 1;
	g.game_sp = chimera_co_create(8u << 20);
	if (!g.game_sp)
	{
		snprintf(err, (size_t)errsz, "error.no_memory_for_the_game_s_stack");
		return 0;
	}
	do
	{
		g.on_game = 1;
		chimera_co_switch(&g.host_sp, g.game_sp);
	} while (!g.started && !g.over && g.frames < BOR_LOAD_FRAMES);
	if (!g.started && !g.over)
	{
		snprintf(err, (size_t)errsz, "error.openbor_did_not_finish_loading" TEXT_ARG "%d", BOR_LOAD_FRAMES);
		return 0;
	}
	if (g.over)
	{
		const char *why = g.stopped[0] ? g.stopped : g.message;
		/* why is OpenBOR's own message, shown as it gave it */
		if (why[0])
			snprintf(err, (size_t)errsz, "error.openbor_could_not_load_because" TEXT_ARG "%s", why);
		else
			snprintf(err, (size_t)errsz, "error.openbor_could_not_load");
		return 0;
	}
	return 1;
}

void bordrv_frame(int render)
{
	g.render = render;
	g.input_read = 0;
	g.pictured = 0;
	send_keys();
	g.on_game = 1;
	chimera_co_switch(&g.host_sp, g.game_sp);
}

const uint32_t *bordrv_video(int *w, int *h)
{
	*w = g.width ? g.width : 320;
	*h = g.height ? g.height : 240;
	return g.picture;
}

const int16_t *bordrv_audio(int *n)
{
	*n = g.audio_frames;
	return g.audio;
}

int bordrv_input_was_read(void) { return g.input_read; }

uint64_t bordrv_frames(void) { return g.frames; }
