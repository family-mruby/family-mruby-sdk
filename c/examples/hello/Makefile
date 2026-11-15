# Build a Family mruby app in C: make -> hello.app.wasm
#
# FMRB_SDK is the SDK's c/ directory (a copy of its two headers, or a git
# submodule of the SDK: FMRB_SDK = family-mruby-sdk/c). CC is `zig cc` by
# default; with clang: make CC=clang TARGET=--target=wasm32 (it needs
# wasm-ld, the lld package).
FMRB_SDK ?= ../..
APP      ?= hello
SRCS     ?= $(wildcard *.c)
CC       := zig cc
TARGET   ?= -target wasm32-freestanding
CFLAGS   ?= -Os
# No libc and no entry point (the firmware calls the hooks), a 16 KB stack.
WASMFLAGS = $(TARGET) -nostdlib -I$(FMRB_SDK) -Wl,--no-entry -Wl,-z,stack-size=16384 -Wl,--strip-all

$(APP).app.wasm: $(SRCS) $(FMRB_SDK)/fmrb_boundary.h $(FMRB_SDK)/fmrb_sdk_version.h
	$(CC) $(WASMFLAGS) $(CFLAGS) $(SRCS) -o $@

clean:
	rm -f $(APP).app.wasm

.PHONY: clean
