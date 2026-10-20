# sources.mk - what native.mk and guest.mk both build: the same files with the
# same defines, so the native reference and the sandboxed core are the same
# program. Included, not run.

ROOT   := ..
SDL    := $(ROOT)/extern/SDL
BOR    := $(ROOT)/extern/openbor/engine
OGG    := $(ROOT)/extern/ogg
VORBIS := $(ROOT)/extern/vorbis
ZLIB   := $(ROOT)/extern/zlib
PNG    := $(ROOT)/extern/libpng
MB     ?= $(MINIBOX_DIR)
# headers made here (the rule is below)
INC_DIR := $(ROOT)/build/include

# ---- SDL 2, upstream, built the way its own Makefile.minimal builds it (the
# SDLPoP core's recipe): the platform-neutral config - dummy video and audio
# drivers, no threads, no timers, no joysticks, no dynamic loading - and the
# portable C of every subsystem, with the software renderer. On top:
#   SDL_CPUINFO_DISABLED  SDL asks the CPU nothing, so every blitter is the C
#                         one on every host
#   DYNAPI_NEEDS_DLOPEN   (without HAVE_DLOPEN) no dynamic API, which would let
#                         an environment variable load another SDL
#   HAVE_MALLOC, HAVE_STDIO_H
#                         SDL allocates and opens files with the C library
SDL_DIRS := src src/atomic src/audio src/audio/dummy src/cpuinfo src/events src/file \
	src/haptic src/haptic/dummy src/hidapi src/joystick src/joystick/dummy src/loadso/dummy \
	src/power src/filesystem/dummy src/locale src/locale/dummy src/misc src/misc/dummy \
	src/render src/render/software src/sensor src/sensor/dummy src/stdlib src/libm \
	src/thread src/thread/generic src/timer src/timer/dummy src/video src/video/yuv2rgb \
	src/video/dummy
SDL_WARN := -w -Wno-error=incompatible-pointer-types
SDL_SRCS := $(sort $(foreach d,$(SDL_DIRS),$(wildcard $(SDL)/$(d)/*.c)))
SDL_DEFS := -DSDL_CPUINFO_DISABLED=1 -DDYNAPI_NEEDS_DLOPEN=1 -DHAVE_MALLOC=1 -DHAVE_STDLIB_H=1 -DHAVE_STDIO_H=1 -DHAVE_STRING_H=1

# ---- zlib (v1.3.2), libpng (v1.6.49, its prebuilt pnglibconf.h and none of
# its CPU-specific filters), libogg (v1.3.5) and libvorbis (v1.3.7): the
# libraries OpenBOR links, from their sources
ZLIB_NAMES := adler32 compress crc32 deflate gzclose gzlib gzread gzwrite infback inffast inflate \
	inftrees trees uncompr zutil
ZLIB_SRCS := $(addprefix $(ZLIB)/,$(addsuffix .c,$(ZLIB_NAMES)))
PNG_NAMES := png pngerror pngget pngmem pngpread pngread pngrio pngrtran pngrutil pngset pngtrans \
	pngwio pngwrite pngwtran pngwutil
PNG_SRCS := $(addprefix $(PNG)/,$(addsuffix .c,$(PNG_NAMES)))
OGG_SRCS := $(OGG)/src/bitwise.c $(OGG)/src/framing.c
VORBIS_NAMES := analysis bitrate block codebook envelope floor0 floor1 info lookup lpc lsp mapping0 mdct \
	psy registry res0 sharedbook smallft synthesis vorbisfile window
VORBIS_SRCS := $(addprefix $(VORBIS)/lib/,$(addsuffix .c,$(VORBIS_NAMES)))
LIB_SRCS := $(ZLIB_SRCS) $(PNG_SRCS) $(OGG_SRCS) $(VORBIS_SRCS)
LIB_DEFS := -DPNG_ARM_NEON_OPT=0 -DPNG_INTEL_SSE_OPT=0 -DPNG_POWERPC_VSX_OPT=0 -DPNG_LOONGARCH_LSX_OPT=0 \
	-DPNG_MIPS_MSA_OPT=0 -DHAVE_UNISTD_H
LIB_INCS := -Icompat -I$(INC_DIR) -I$(ZLIB) -I$(PNG) -I$(OGG)/include -I$(VORBIS)/include -I$(VORBIS)/lib

# ---- OpenBOR, upstream (extern/openbor): every C file of engine/ and
# engine/source/ as its CMakeLists.txt takes them, with the scalers
# (gfxlib) and the SDL port, without WebM video, OpenGL and the tests (its
# CMakeLists.txt drops every path with "tes" in it, and so does this); the
# SDL port's main() is the core's way in (sdlport.c, renamed by BOR_MAIN).
BOR_SRCS := $(sort $(wildcard $(BOR)/*.c) \
	$(shell find $(BOR)/source -name '*.c' -not -path '$(BOR)/source/*tes*' -not -path '*/gfxlib/*' \
		-not -path '*/webmlib/*' 2>/dev/null) \
	$(wildcard $(BOR)/source/gfxlib/*.c) \
	$(filter-out %gl.c,$(wildcard $(BOR)/sdl/*.c)))
BOR_INCS := -I$(BOR) -I$(BOR)/source -I$(BOR)/source/gamelib -I$(BOR)/source/gfxlib -I$(BOR)/source/openborscript \
	-I$(BOR)/source/pnglib -I$(BOR)/source/preprocessorlib -I$(BOR)/source/ramlib -I$(BOR)/source/randlib \
	-I$(BOR)/source/scriptlib -I$(BOR)/source/tracelib2 -I$(BOR)/source/webmlib -I$(BOR)/sdl
# __DATE__ is the date of the OpenBOR commit built (compat/version.h), not
# the day of the build: OpenBOR shows it in its log and menus, and the same
# OpenBOR shows the same everywhere
BOR_DATE := Oct 18 2026
BOR_DEFS := -DSDL=1 -DLINUX -DOV_EXCLUDE_STATIC_CALLBACKS -DCHIMERA_CORE -D_GNU_SOURCE=1 -std=gnu99 -fsigned-char \
	-include compat/chimera-bor.h -Wno-builtin-macro-redefined '-D__DATE__="$(BOR_DATE)"'
BOR_MAIN := -Dmain=openbor_sdl_main

# ---- the core
CORE_NAMES := openbor-driver seams coroutine wbx-entry
CORE_HDRS := openbor-driver.h coroutine.h

# ---- the calls the core answers itself (seams.c)
WRAPS := SDL_GetPerformanceCounter SDL_GetPerformanceFrequency SDL_GetTicks SDL_GetTicks64 \
	SDL_Delay SDL_Init SDL_InitSubSystem SDL_OpenAudioDevice SDL_CloseAudioDevice SDL_PauseAudioDevice \
	SDL_LockAudioDevice SDL_UnlockAudioDevice SDL_RenderPresent SDL_PollEvent SDL_GetKeyboardState \
	SDL_CreateThread SDL_ShowSimpleMessageBox \
	fopen opendir mkdir chdir time localtime gettimeofday usleep nanosleep exit getenv dirExists sysinfo \
	mallinfo2 localtime_r mktime ctime
WRAP_FLAGS := $(foreach w,$(WRAPS),-Wl,--wrap=$(w))

# the patch series goes onto the submodule before anything of OpenBOR builds
PATCH_STAMP := $(ROOT)/build/patches.stamp
$(PATCH_STAMP): $(wildcard $(ROOT)/patches/*.patch) apply-patches.sh
	sh apply-patches.sh
	@mkdir -p $(dir $@)
	@touch $@

# headers made here: SDL's under SDL2/ and at the top (OpenBOR includes
# <SDL.h>), libpng's configuration, OpenBOR's version
SDL_HDRS := $(wildcard $(SDL)/include/*.h)
$(INC_DIR)/.stamp: $(SDL_HDRS) $(PNG)/scripts/pnglibconf.h.prebuilt compat/version.h
	@mkdir -p $(INC_DIR)/SDL2
	cp $(SDL_HDRS) $(INC_DIR)/SDL2/
	cp $(SDL_HDRS) $(INC_DIR)/
	cp $(PNG)/scripts/pnglibconf.h.prebuilt $(INC_DIR)/pnglibconf.h
	cp compat/version.h $(INC_DIR)/version.h
	@touch $@

COMMON_CFLAGS := -O2 -fno-strict-aliasing $(SDL_DEFS) -I$(INC_DIR) -I$(SDL)/include

# Every object depends on the flags it was built with: a change to them
# rebuilds it.
define flags_stamp
$(shell mkdir -p $(1); printf '%s\n' '$(2)' | cmp -s - $(1)/flags || printf '%s\n' '$(2)' > $(1)/flags)
endef
