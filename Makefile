# Detects the host OS (and Linux distribution) at make-time and configures
# the build accordingly.
#
#   Linux (Ubuntu, Red Hat):  builds c_listener      (gcc)
#   Windows (MinGW-w64):       builds c_listener.exe  (gcc)  and,
#                              if NASM is present,    asm_listener.exe
#
# The x64 assembly listener (net-listen.asm) is Windows/Winsock-only, so it
# is built only on Windows. The C listener is portable and built everywhere.
#
#   make            # build everything appropriate for this OS
#   make c          # build only the C listener
#   make asm        # build only the assembly listener (Windows only)
#   make info       # print the detected build configuration
#   make clean

# GNU Make pre-defines CC as `cc` (origin "default"), and `?=` will NOT
# override that built-in default. Since `cc` does not exist on some
# toolchains (notably MinGW-w64, which ships only `gcc`), force gcc unless
# CC was set explicitly via the environment or command line.
ifeq ($(origin CC),default)
    CC := gcc
endif
NASM    ?= nasm
CFLAGS  ?= -O2 -Wall -Wextra
C_SRC   := c_listener.c
ASM_SRC := net-listen.asm
ASM_OBJ := net-listen.obj

ifeq ($(OS),Windows_NT)
    PLATFORM := windows
    C_BIN    := c_listener.exe
    ASM_BIN  := asm_listener.exe
    LDLIBS   := -lws2_32
    RM       := del /q
    NULDEV   := NUL
    # Build the asm listener too, but only if NASM is on PATH.
    HAVE_NASM := $(shell where $(NASM) >NUL 2>&1 && echo yes)
    ifeq ($(HAVE_NASM),yes)
        TARGETS := $(C_BIN) $(ASM_BIN)
    else
        TARGETS := $(C_BIN)
    endif
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
        PLATFORM := linux
        C_BIN    := c_listener
        LDLIBS   :=
        RM       := rm -f
        NULDEV   := /dev/null
        TARGETS  := $(C_BIN)
        ifneq ($(wildcard /etc/os-release),)
            DISTRO_ID      := $(shell . /etc/os-release && echo $$ID)
            DISTRO_VERSION := $(shell . /etc/os-release && echo $$VERSION_ID)
        endif
        SUPPORTED_DISTROS := ubuntu debian rhel centos fedora rocky almalinux
        ifeq ($(filter $(DISTRO_ID),$(SUPPORTED_DISTROS)),)
            $(warning Untested Linux distribution '$(DISTRO_ID)'; build will proceed but is not verified.)
        endif
    else
        $(error Unsupported OS: $(UNAME_S). Supported: Linux (Ubuntu/RHEL), Windows.)
    endif
endif

.PHONY: all c asm info clean

all: info $(TARGETS)

c: $(C_BIN)

info:
	@echo === net-listen build ===
	@echo Platform : $(PLATFORM)
ifeq ($(PLATFORM),linux)
	@echo Distro   : $(DISTRO_ID) $(DISTRO_VERSION)
endif
	@echo Compiler : $(CC)
	@echo Flags    : $(CFLAGS)
	@echo Targets  : $(TARGETS)
	@echo ========================

$(C_BIN): $(C_SRC)
	$(CC) $(CFLAGS) $(C_SRC) -o $(C_BIN) $(LDLIBS)

ifeq ($(OS),Windows_NT)
asm: $(ASM_BIN)

$(ASM_OBJ): $(ASM_SRC)
	$(NASM) -f win64 $(ASM_SRC) -o $(ASM_OBJ)

$(ASM_BIN): $(ASM_OBJ)
	$(CC) -nostartfiles -Wl,-e,start $(ASM_OBJ) -o $(ASM_BIN) -lws2_32 -lkernel32
else
asm:
	@echo "asm_listener is Windows-only (net-listen.asm uses Win64 + Winsock); skipping on $(PLATFORM)."
endif

clean:
	-$(RM) c_listener c_listener.exe asm_listener.exe $(ASM_OBJ) 2> $(NULDEV)
