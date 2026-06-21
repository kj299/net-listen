# net-listen

Two minimal network listeners — one in portable C, one in raw x64 assembly —
that bind a TCP (and, for the C build, a UDP) port and print whatever a client
sends. Useful as a netcat-style probe and as a small, readable example of the
sockets API.

| Binary               | Source           | Platforms                     | Protocols | Ports                    |
| -------------------- | ---------------- | ----------------------------- | --------- | ------------------------ |
| `c_listener`(`.exe`) | `c_listener.c`   | Linux (Ubuntu, RHEL), Windows | TCP + UDP | both supplied on the CLI |
| `asm_listener.exe`   | `net-listen.asm` | Windows only                  | TCP       | hard-coded to `1234`     |

The C build is the full implementation: argument validation, native error
reporting (`WSAGetLastError`/`FormatMessage` on Windows, `errno`/`strerror` on
Linux), `select()`-based multiplexing of the TCP and UDP sockets so neither is
starved, `SO_REUSEADDR`, and graceful Ctrl+C shutdown. It compiles unchanged on
Linux and Windows via a small platform shim at the top of the source.

The assembly build is a deliberately small, **Windows-only** TCP counterpart
that demonstrates the Microsoft x64 calling convention and direct Winsock import
resolution from NASM. Assembly is inherently platform-specific, so there is no
Linux equivalent.

## Build

The supplied `Makefile` detects the host OS (and, on Linux, the distribution)
and builds the right targets automatically.

### Linux (Ubuntu, Red Hat)

```
make            # builds ./c_listener
```

Requires `gcc` and `make` (`sudo apt install build-essential` on Ubuntu,
`sudo dnf install gcc make` on RHEL/Fedora).

### Windows

The build chain is MinGW-w64 (gcc + ld) plus NASM. Both ship in the
[WinLibs](https://winlibs.com/) bundle:

```
winget install -e --id BrechtSanders.WinLibs.POSIX.UCRT
```

Then either:

```
mingw32-make            # builds c_listener.exe and asm_listener.exe
build.bat               # equivalent, no make required
```

`mingw32-make c` / `mingw32-make asm` build a single target.
`make clean` / `build.bat clean` remove all generated files.
If NASM is not on `PATH`, the Makefile builds only `c_listener.exe`.

The C source also compiles with MSVC: `cl c_listener.c ws2_32.lib`.

## Run

```
# Linux
./c_listener 1234 5678              # TCP/1234 + UDP/5678

# Windows
c_listener.exe 1234 5678            # TCP/1234 + UDP/5678
asm_listener.exe                    # TCP/1234 only
```

Test from another shell:

```
# Linux
printf 'hi' | nc 127.0.0.1 1234           # TCP
printf 'hi' | nc -u -w1 127.0.0.1 5678    # UDP

# Windows (PowerShell)
(New-Object Net.Sockets.TcpClient).Connect('127.0.0.1',1234)
$u=New-Object Net.Sockets.UdpClient; `
  [void]$u.Send([Text.Encoding]::ASCII.GetBytes('hi'),2,'127.0.0.1',5678)
```

Press Ctrl+C to stop the C listener cleanly. The assembly listener has no
console handler — Ctrl+C terminates it via the default Win32 behaviour.
