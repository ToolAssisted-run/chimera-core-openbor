/* openbor-driver.h - OpenBOR as a Chimera machine (openbor-driver.c). */
#ifndef OPENBOR_DRIVER_H
#define OPENBOR_DRIVER_H

#include <stdint.h>
#include <stdio.h>

/* the picture's capacity (waterbox.config), the sound */
#define BOR_MAX_W 1920
#define BOR_MAX_H 1080
#define BOR_AUDIO_RATE 44100
#define BOR_FPS 60
/* loading a game takes at most this many frames (five minutes of the
 * machine's time; each loading screen OpenBOR draws is a frame) */
#define BOR_LOAD_FRAMES (BOR_FPS * 300)

/* the controls, in waterbox.config's order: for each of the four players
 * Up, Down, Left, Right, Attack, Attack 2, Attack 3, Attack 4, Jump,
 * Special and Start; then Escape */
#define BOR_PLAYERS 4
#define BOR_PER_PLAYER 11
#define BOR_BTN_ESC (BOR_PLAYERS * BOR_PER_PLAYER)
#define BOR_BTN_COUNT (BOR_BTN_ESC + 1)

#ifdef __cplusplus
extern "C" {
#endif

/* --- the calls of wbx-entry.c */
int bordrv_init(char *err, int errsz);
void bordrv_set_button(int index, int on);
void bordrv_frame(int render);
const uint32_t *bordrv_video(int *w, int *h);
const int16_t *bordrv_audio(int *n);
int bordrv_input_was_read(void);
uint64_t bordrv_frames(void);
int32_t bordrv_saves_count(void);
const char *bordrv_saves_name(int32_t i);
int64_t bordrv_saves_size(int32_t i);
const uint8_t *bordrv_saves_data(int32_t i);

/* --- what seams.c hands over */
uint64_t bordrv_now_us(void);
int64_t bordrv_unix_time(void);
void bordrv_delay_us(uint64_t us);
int bordrv_on_game_stack(void);
const uint8_t *bordrv_keyboard_state(void);
void bordrv_audio_open(void *callback, void *userdata);
void bordrv_audio_close(void);
void bordrv_audio_pause(int paused);
void bordrv_present(void *renderer);
int bordrv_idle_pump(void);
FILE *bordrv_fopen(const char *path, const char *mode, int *handled);
void bordrv_game_exit(int code) __attribute__((noreturn));
void bordrv_message(const char *title, const char *text);

#ifdef __cplusplus
}
#endif

#endif
