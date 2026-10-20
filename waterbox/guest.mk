# guest.mk - core.wbx: the same SDL, libraries, OpenBOR and core sources as
# native.mk, built with miniBox's musl guest toolchain (C only) and linked at
# the guest base. Objects land in build/guest; core.wbx is checked by
# miniBox's check-wbx.sh (no thread-local storage, no %fs, no red zone) before
# it counts as built.
#
# Usage: make -f guest.mk -j$(nproc) [MB=<miniBox checkout>]

.DEFAULT_GOAL := all
include sources.mk

B      := $(ROOT)/build/guest
MBUILD := $(MB)/build/meson-linux
CC     := $(MBUILD)/musl-gcc

# BizHawk waterbox's frozen guest flags, as miniBox's source/guest/meson.build
# gives them to a C guest
WBFLAGS := -fvisibility=hidden -mcmodel=large -mno-red-zone -mstack-protector-guard=global \
	-fno-stack-protector -fno-pic -fno-pie -fcf-protection=none -DNDEBUG -DCHIMERA_GUEST
MBINCS := -I$(MB)/extern/emulibc -I$(MB)/source/guest/include -I$(MB)/extern/jsmn

SDL_CFLAGS := $(WBFLAGS) $(COMMON_CFLAGS) $(SDL_WARN)
LIB_CFLAGS := $(WBFLAGS) $(COMMON_CFLAGS) $(LIB_DEFS) $(LIB_INCS) -w
BOR_CFLAGS := $(WBFLAGS) $(COMMON_CFLAGS) $(BOR_DEFS) $(LIB_INCS) $(BOR_INCS) -w
CORE_CFLAGS := $(WBFLAGS) $(COMMON_CFLAGS) $(BOR_DEFS) $(MBINCS) $(LIB_INCS) -I. -Wall -Wno-unused-function

$(call flags_stamp,$(B),$(CC) | $(SDL_CFLAGS) | $(LIB_CFLAGS) | $(BOR_CFLAGS) | $(BOR_MAIN) | $(CORE_CFLAGS))

SDL_OBJS := $(patsubst $(SDL)/%.c,$(B)/sdl/%.o,$(SDL_SRCS))
LIB_OBJS := $(patsubst $(ROOT)/extern/%.c,$(B)/lib/%.o,$(LIB_SRCS))
BOR_OBJS := $(patsubst $(BOR)/%.c,$(B)/bor/%.o,$(BOR_SRCS))
CORE_OBJS := $(addprefix $(B)/core/,$(addsuffix .o,$(CORE_NAMES)))

all: $(B)/core.wbx

$(CC):
	@echo "miniBox's C guest toolchain is missing: $(CC)" >&2
	@echo "build it: meson setup $(MB)/build/meson-linux $(MB) && ninja -C $(MB)/build/meson-linux" >&2
	@false

$(B)/sdl/%.o: $(SDL)/%.c $(INC_DIR)/.stamp $(B)/flags | $(CC)
	@mkdir -p $(dir $@)
	$(CC) $(SDL_CFLAGS) -c -o $@ $<

$(B)/lib/%.o: $(ROOT)/extern/%.c $(INC_DIR)/.stamp $(B)/flags | $(CC)
	@mkdir -p $(dir $@)
	$(CC) $(LIB_CFLAGS) -c -o $@ $<

$(B)/bor/%.o: $(BOR)/%.c $(PATCH_STAMP) $(INC_DIR)/.stamp $(B)/flags | $(CC)
	@mkdir -p $(dir $@)
	$(CC) $(BOR_CFLAGS) $(if $(filter %/sdlport.c,$<),$(BOR_MAIN)) -c -o $@ $<

$(B)/core/%.o: %.c $(CORE_HDRS) $(PATCH_STAMP) $(INC_DIR)/.stamp $(B)/flags | $(CC)
	@mkdir -p $(dir $@)
	$(CC) $(CORE_CFLAGS) -c -o $@ $<

$(B)/core.wbx: $(CORE_OBJS) $(BOR_OBJS) $(LIB_OBJS) $(SDL_OBJS)
	$(CC) -static -no-pie -Wl,--eh-frame-hdr,-O2 -Wl,-z,stack-size=8388608 -T $(MB)/source/guest/linkscript.T \
		-o $@.tmp $^ $(MBUILD)/source/guest/emulibc.c.o $(WRAP_FLAGS) -lgcc
	sh $(MB)/source/guest/check-wbx.sh $@.tmp
	mv $@.tmp $@

clean:
	rm -rf $(B)

.PHONY: all clean
