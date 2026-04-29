# Detects the host OS (and Linux distribution) at make-time and configures
# the build accordingly. Supports Windows (MinGW/MSYS2), Ubuntu, and RHEL.

CC      ?= gcc
CFLAGS  ?= -Wall -O2
SRC     := c_listener.c

ifeq ($(OS),Windows_NT)
    PLATFORM := windows
    BIN      := c_listener.exe
    LDLIBS   := -lws2_32
    RM       := del /Q /F
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
        PLATFORM := linux
        BIN      := c_listener
        LDLIBS   :=
        RM       := rm -f
        ifneq ($(wildcard /etc/os-release),)
            DISTRO_ID      := $(shell . /etc/os-release && echo $$ID)
            DISTRO_VERSION := $(shell . /etc/os-release && echo $$VERSION_ID)
        endif
        SUPPORTED_DISTROS := ubuntu debian rhel centos fedora rocky almalinux
        ifneq ($(filter $(DISTRO_ID),$(SUPPORTED_DISTROS)),)
            DISTRO_OK := yes
        else
            $(warning Untested Linux distribution '$(DISTRO_ID)'; build will proceed but is not verified.)
        endif
    else
        $(error Unsupported OS: $(UNAME_S). Supported: Linux (Ubuntu/RHEL), Windows.)
    endif
endif

.PHONY: all info clean

all: info $(BIN)

info:
	@echo "=== net-listen build ==="
	@echo "Platform : $(PLATFORM)"
ifeq ($(PLATFORM),linux)
	@echo "Distro   : $(DISTRO_ID) $(DISTRO_VERSION)"
endif
	@echo "Compiler : $(CC)"
	@echo "Flags    : $(CFLAGS)"
	@echo "Libs     : $(LDLIBS)"
	@echo "Output   : $(BIN)"
	@echo "========================"

$(BIN): $(SRC)
	$(CC) $(CFLAGS) $(SRC) -o $(BIN) $(LDLIBS)

clean:
	-$(RM) c_listener c_listener.exe
