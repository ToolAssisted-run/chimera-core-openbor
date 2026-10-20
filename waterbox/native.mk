# native.mk - the native reference: the same SDL, libraries, OpenBOR and core
# sources as guest.mk, built for this computer, plus the two harnesses
# (run-native drives the core's calls directly; run-wbx drives core.wbx
# through the miniBox host exactly as Chimera does). The math functions are
# the sandbox's own (make-native-libm.sh). Objects land in build/native.
#
# Usage: make -f native.mk -j$(nproc) [MB=<miniBox checkout>]

.DEFAULT_GOAL := all
include sources.mk

B := $(ROOT)/build/native
MBINCS := -Inative-shim -I$(MB)/source/guest/include -I$(MB)/extern/jsmn
LIBM := $(ROOT)/build/native-libm

# with debugging information (gdb on the native reference); the code is the
# same as without
SDL_CFLAGS := -g $(COMMON_CFLAGS) $(SDL_WARN)
LIB_CFLAGS := -g $(COMMON_CFLAGS) $(LIB_DEFS) $(LIB_INCS) -w
BOR_CFLAGS := -g $(COMMON_CFLAGS) $(BOR_DEFS) $(LIB_INCS) $(BOR_INCS) -w
CORE_CFLAGS := -g $(COMMON_CFLAGS) $(BOR_DEFS) $(MBINCS) $(LIB_INCS) -I. -Wall -Wno-unused-function

$(call flags_stamp,$(B),$(SDL_CFLAGS) | $(LIB_CFLAGS) | $(BOR_CFLAGS) | $(BOR_MAIN) | $(CORE_CFLAGS))

SDL_OBJS := $(patsubst $(SDL)/%.c,$(B)/sdl/%.o,$(SDL_SRCS))
LIB_OBJS := $(patsubst $(ROOT)/extern/%.c,$(B)/lib/%.o,$(LIB_SRCS))
BOR_OBJS := $(patsubst $(BOR)/%.c,$(B)/bor/%.o,$(BOR_SRCS))
CORE_OBJS := $(addprefix $(B)/core/,$(addsuffix .o,$(CORE_NAMES)))

all: $(B)/run-native $(B)/run-wbx

$(B)/sdl/%.o: $(SDL)/%.c $(INC_DIR)/.stamp $(B)/flags
	@mkdir -p $(dir $@)
	gcc $(SDL_CFLAGS) -c -o $@ $<

$(B)/lib/%.o: $(ROOT)/extern/%.c $(INC_DIR)/.stamp $(B)/flags
	@mkdir -p $(dir $@)
	gcc $(LIB_CFLAGS) -c -o $@ $<

$(B)/bor/%.o: $(BOR)/%.c $(PATCH_STAMP) $(INC_DIR)/.stamp $(B)/flags
	@mkdir -p $(dir $@)
	gcc $(BOR_CFLAGS) $(if $(filter %/sdlport.c,$<),$(BOR_MAIN)) -c -o $@ $<

$(B)/core/%.o: %.c $(CORE_HDRS) $(PATCH_STAMP) $(INC_DIR)/.stamp $(B)/flags
	@mkdir -p $(dir $@)
	gcc $(CORE_CFLAGS) -c -o $@ $<

$(B)/core/run-native.o: run-native.c gate-harness.h input-names.h $(B)/flags
	@mkdir -p $(dir $@)
	gcc -O2 -Wall -DGATE_NATIVE -I. -c -o $@ $<

$(LIBM)/libchimera-m.a:
	bash make-native-libm.sh $(MB)

$(B)/run-native: $(CORE_OBJS) $(BOR_OBJS) $(LIB_OBJS) $(SDL_OBJS) $(B)/core/run-native.o $(LIBM)/libchimera-m.a
	gcc -no-pie -o $@ $(filter %.o,$^) $(LIBM)/libchimera-m.a $(WRAP_FLAGS) $$(cat $(LIBM)/wrap-flags) -lm

# run-wbx links the miniBox host library
MBHOST := $(MB)/build/meson-linux/source/host
$(B)/run-wbx: run-wbx.c gate-harness.h input-names.h $(B)/flags
	gcc -O2 -Wall -I. -I$(MB)/source/host -o $@ run-wbx.c $(MBHOST)/libminiboxhost.so -Wl,-rpath,$(MBHOST)

clean:
	rm -rf $(B)

.PHONY: all clean
