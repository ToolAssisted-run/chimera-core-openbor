/* wbx-entry.c - the chimera guest ABI over openbor-driver.
 *
 * Compiles identically for the guest (miniBox emulibc) and for the native
 * reference (native-shim/emulibc.h): the same driver and the same exports,
 * one in the sandbox and one out of it.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <emulibc.h>

#include "openbor-driver.h"

static char g_load_error[1024];

/* Turbo: the picture is not read back; the game draws whatever happens */
ECL_INVISIBLE int chimera_render_enabled = 1;

ECL_EXPORT const char *GetLoadError(void) { return g_load_error; }

ECL_EXPORT int Init(void) { return bordrv_init(g_load_error, (int)sizeof g_load_error); }

ECL_EXPORT void SetButton(int32_t index, int32_t state) { bordrv_set_button(index, state); }

ECL_EXPORT void FrameAdvance(uint64_t packed)
{
	(void)packed;
	bordrv_frame(chimera_render_enabled);
}

ECL_EXPORT void SetRenderingEnabled(int on) { chimera_render_enabled = on != 0; }

ECL_EXPORT uint32_t *GetVideoBgra(void)
{
	int w, h;
	return (uint32_t *)bordrv_video(&w, &h);
}
ECL_EXPORT int GetVideoWidth(void)
{
	int w, h;
	bordrv_video(&w, &h);
	return w;
}
ECL_EXPORT int GetVideoHeight(void)
{
	int w, h;
	bordrv_video(&w, &h);
	return h;
}

ECL_EXPORT int16_t *GetAudio(void)
{
	int n;
	return (int16_t *)bordrv_audio(&n);
}
ECL_EXPORT int GetAudioSampleCount(void)
{
	int n;
	bordrv_audio(&n);
	return n;
}

ECL_EXPORT int GetVsyncNumerator(void) { return BOR_FPS; }
ECL_EXPORT int GetVsyncDenominator(void) { return 1; }

/* a frame in which OpenBOR did not read the keys is a lag frame */
ECL_EXPORT int InputWasRead(void) { return bordrv_input_was_read(); }

/* Emulator > Export Save Data: what OpenBOR keeps in Saves/ */
ECL_EXPORT int32_t GetSaveDataFileCount(void) { return bordrv_saves_count(); }
ECL_EXPORT const char *GetSaveDataFileName(int32_t i) { return bordrv_saves_name(i); }
ECL_EXPORT int64_t GetSaveDataFileSize(int32_t i) { return bordrv_saves_size(i); }
ECL_EXPORT const uint8_t *GetSaveDataFileBuffer(int32_t i) { return bordrv_saves_data(i); }

ECL_EXPORT int GetMemoryDomainCount(void) { return 0; }
ECL_EXPORT const char *GetMemoryDomainName(int i) { (void)i; return ""; }
ECL_EXPORT uint8_t *GetMemoryDomainPtr(int i) { (void)i; return NULL; }
ECL_EXPORT int64_t GetMemoryDomainSize(int i) { (void)i; return 0; }
ECL_EXPORT int GetMemoryDomainWritable(int i) { (void)i; return 0; }

/* the machine's own clock, in frames */
ECL_EXPORT uint64_t GetCycleCount(void) { return bordrv_frames(); }
