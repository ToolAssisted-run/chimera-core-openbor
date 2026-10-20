/* seams.c - everything OpenBOR reaches outside itself, answered by the core.
 *
 * Linked with -Wl,--wrap=<name> for each __wrap_ below, in both builds
 * (sources.mk lists them): a call to SDL_Delay from OpenBOR (or from SDL
 * itself) lands in __wrap_SDL_Delay, and SDL and the C library are otherwise
 * used as they are. SDL is the real SDL 2, built from source with its
 * minimal configuration (the dummy video driver, no threads, no timers, no
 * CPU feature dispatch).
 *
 *   - time: the performance counter, the tick count, SDL_Delay, usleep,
 *     nanosleep, time, gettimeofday, localtime, localtime_r, mktime and ctime
 *     are the core's clock and calendar (openbor-driver.c), in UTC; a wait is
 *     where the clock moves.
 *   - SDL_Init: video and events only; timers, joysticks and the rest need
 *     threads or a host.
 *   - the sound device: its callback is recorded and the driver pulls it.
 *     Only 44100 Hz 16-bit stereo is offered: OpenBOR tries 24-bit 48000 Hz
 *     first and falls back to exactly that.
 *   - presenting: the driver reads the picture back and ends the frame.
 *   - files: the .pak is read where Chimera mounted it; Saves/ is in the
 *     core's memory, Logs/ goes to the error output, ScreenShots/ is
 *     refused; nothing of the computer's own (/proc, /sys, /dev) is opened;
 *     there are no folders to list, make or change to; no environment
 *     variable is seen.
 *   - the computer's memory (sysinfo) is the same figure everywhere.
 *   - threads: none (OpenBOR starts them only for WebM video, not built).
 *   - exit: the game ending parks it instead of ending the process.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <dirent.h>
#include <errno.h>
#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <SDL.h>

#include "compat/chimera-bor.h"
#include "openbor-driver.h"

/* ----------------------------------------------------------------- time */

#define US_PER_MS 1000ull

Uint64 __wrap_SDL_GetPerformanceCounter(void) { return bordrv_now_us(); }
Uint64 __wrap_SDL_GetPerformanceFrequency(void) { return 1000000ull; }
Uint32 __wrap_SDL_GetTicks(void) { return (Uint32)(bordrv_now_us() / US_PER_MS); }
Uint64 __wrap_SDL_GetTicks64(void) { return bordrv_now_us() / US_PER_MS; }
void __wrap_SDL_Delay(Uint32 ms) { bordrv_delay_us((uint64_t)ms * US_PER_MS); }

int __wrap_usleep(useconds_t us)
{
	bordrv_delay_us(us);
	return 0;
}

int __wrap_nanosleep(const struct timespec *req, struct timespec *rem)
{
	if (req) bordrv_delay_us((uint64_t)req->tv_sec * 1000000ull + (uint64_t)req->tv_nsec / 1000ull);
	if (rem) rem->tv_sec = rem->tv_nsec = 0;
	return 0;
}

time_t __wrap_time(time_t *t)
{
	time_t now = (time_t)bordrv_unix_time();
	if (t) *t = now;
	return now;
}

/* the machine's calendar is UTC */
struct tm *__wrap_localtime(const time_t *t)
{
	static struct tm tm;
	return gmtime_r(t, &tm);
}

struct tm *__wrap_localtime_r(const time_t *t, struct tm *tm) { return gmtime_r(t, tm); }

time_t __wrap_mktime(struct tm *tm) { return timegm(tm); }

char *__wrap_ctime(const time_t *t)
{
	static char buf[32];
	struct tm tm;
	return asctime_r(gmtime_r(t, &tm), buf);
}

int __wrap_gettimeofday(struct timeval *tv, void *tz)
{
	(void)tz;
	if (tv)
	{
		tv->tv_sec = (time_t)bordrv_unix_time();
		tv->tv_usec = (suseconds_t)(bordrv_now_us() % 1000000ull);
	}
	return 0;
}

/* ------------------------------------------------------------------- init */

int __real_SDL_Init(Uint32 flags);
int __real_SDL_InitSubSystem(Uint32 flags);
static const Uint32 k_unavailable = SDL_INIT_TIMER | SDL_INIT_AUDIO | SDL_INIT_JOYSTICK |
	SDL_INIT_HAPTIC | SDL_INIT_GAMECONTROLLER | SDL_INIT_SENSOR;

int __wrap_SDL_Init(Uint32 flags)
{
	/* SDL's dummy video driver, asked for by name over anything else */
	SDL_SetHintWithPriority(SDL_HINT_VIDEODRIVER, "dummy", SDL_HINT_OVERRIDE);
	SDL_SetHintWithPriority(SDL_HINT_RENDER_DRIVER, "software", SDL_HINT_OVERRIDE);
	return __real_SDL_Init(flags & ~k_unavailable);
}

int __wrap_SDL_InitSubSystem(Uint32 flags)
{
	if (flags & k_unavailable) return SDL_SetError("not in this machine");
	return __real_SDL_InitSubSystem(flags);
}

SDL_Thread *__wrap_SDL_CreateThread(SDL_ThreadFunction fn, const char *name, void *data)
{
	(void)fn; (void)name; (void)data;
	SDL_SetError("no threads in this machine");
	return NULL;
}

int __wrap_SDL_ShowSimpleMessageBox(Uint32 flags, const char *title, const char *message, SDL_Window *window)
{
	(void)flags; (void)window;
	bordrv_message(title, message);
	return 0;
}

/* ------------------------------------------------------------------ sound */

SDL_AudioDeviceID __wrap_SDL_OpenAudioDevice(const char *device, int iscapture, const SDL_AudioSpec *desired,
	SDL_AudioSpec *obtained, int allowed_changes)
{
	(void)device; (void)allowed_changes;
	if (iscapture || !desired || desired->freq != BOR_AUDIO_RATE || desired->format != AUDIO_S16SYS ||
		desired->channels != 2 || !desired->callback)
	{
		SDL_SetError("the core's sound device is 44100 Hz 16-bit stereo");
		return 0;
	}
	if (obtained) *obtained = *desired;
	bordrv_audio_open((void *)desired->callback, desired->userdata);
	return 2;
}

void __wrap_SDL_CloseAudioDevice(SDL_AudioDeviceID dev) { (void)dev; bordrv_audio_close(); }
void __wrap_SDL_PauseAudioDevice(SDL_AudioDeviceID dev, int pause) { (void)dev; bordrv_audio_pause(pause); }
/* one thread: the mixer never runs beside the game */
void __wrap_SDL_LockAudioDevice(SDL_AudioDeviceID dev) { (void)dev; }
void __wrap_SDL_UnlockAudioDevice(SDL_AudioDeviceID dev) { (void)dev; }

/* ------------------------------------------------------- picture and input */

void __wrap_SDL_RenderPresent(SDL_Renderer *renderer) { bordrv_present(renderer); }

int __real_SDL_PollEvent(SDL_Event *event);
int __wrap_SDL_PollEvent(SDL_Event *event)
{
	int got = __real_SDL_PollEvent(event);
	if (!got && bordrv_idle_pump())
		got = __real_SDL_PollEvent(event);
	return got;
}

const Uint8 *__wrap_SDL_GetKeyboardState(int *numkeys)
{
	if (numkeys) *numkeys = SDL_NUM_SCANCODES;
	return bordrv_keyboard_state();
}

/* ------------------------------------------------------------------ files */

FILE *__real_fopen(const char *path, const char *mode);
FILE *__wrap_fopen(const char *path, const char *mode)
{
	/* the harnesses' own files are theirs */
	if (!bordrv_on_game_stack()) return __real_fopen(path, mode);
	/* nothing of the computer's own (/proc/self/statm, the memory in use);
	 * the files Chimera mounted are named from the root, "/test.pak" */
	if (!strncmp(path, "/proc/", 6) || !strncmp(path, "/sys/", 5) || !strncmp(path, "/dev/", 5))
	{
		errno = ENOENT;
		return NULL;
	}
	int handled = 0;
	FILE *f = bordrv_fopen(path, mode, &handled);
	if (handled) return f;
	/* anything else is read where Chimera mounted it; nothing else is written */
	if (strchr(mode, 'w') || strchr(mode, 'a') || strchr(mode, '+'))
	{
		errno = EACCES;
		return NULL;
	}
	return __real_fopen(path, mode);
}

/* The machine's memory: the same on every computer. OpenBOR logs it, and a
 * game's scripts and the system menu can read it. */
int __wrap_sysinfo(struct sysinfo *info)
{
	memset(info, 0, sizeof *info);
	info->totalram = 1536ul << 20;
	info->freeram = 1024ul << 20;
	info->mem_unit = 1;
	info->procs = 1;
	return 0;
}

/* the memory the C library's allocator holds: nothing is said of it (an
 * out-of-memory message names it; the sandbox's C library has no such call) */
struct mallinfo2 __wrap_mallinfo2(void)
{
	struct mallinfo2 m;
	memset(&m, 0, sizeof m);
	return m;
}

/* OpenBOR's folders (Paks, Saves, Logs, ScreenShots) exist; it lists none */
int __wrap_dirExists(char *name, int create) { (void)name; (void)create; return 1; }

/* the harnesses' own calls are theirs; the game's are answered here */
DIR *__real_opendir(const char *name);
DIR *__wrap_opendir(const char *name)
{
	if (!bordrv_on_game_stack()) return __real_opendir(name);
	errno = ENOENT;
	return NULL;
}

int __real_mkdir(const char *path, mode_t mode);
int __wrap_mkdir(const char *path, mode_t mode)
{
	return bordrv_on_game_stack() ? 0 : __real_mkdir(path, mode);
}

int __real_chdir(const char *path);
int __wrap_chdir(const char *path)
{
	return bordrv_on_game_stack() ? 0 : __real_chdir(path);
}
char *__real_getenv(const char *name);
char *__wrap_getenv(const char *name) { return bordrv_on_game_stack() ? NULL : __real_getenv(name); }

void __real_exit(int code) __attribute__((noreturn));
void __wrap_exit(int code)
{
	if (bordrv_on_game_stack()) bordrv_game_exit(code);
	__real_exit(code);
}
