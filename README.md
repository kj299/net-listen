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
Linux), and a single `select()` event loop that polls the UDP socket, the TCP
listener, and every connected TCP client together — so multiple TCP clients are
served concurrently and UDP is never starved while a client is busy. Plus
`SO_REUSEADDR` and graceful Ctrl+C shutdown. It compiles unchanged on Linux and
Windows via a small platform shim at the top of the source.

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

Both listeners bind `0.0.0.0` — **all interfaces**, not just localhost — so
anything that can reach the machine can connect. Received bytes are printed
with non-printable characters replaced by `.`, so a remote peer cannot inject
terminal escape sequences into your console.

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

## Smoke test (Windows)

`smoketest.ps1` iterates across the tool's capabilities and validates that
each works as expected: argument validation, TCP and UDP receipt, `select()`
multiplexing in a single instance, graceful shutdown, and the assembly
listener's TCP echo. It prints `[PASS]`/`[FAIL]`/`[WARN]` per check and exits
with the number of failures (0 = all good). Every run also writes the full
output to `smoketest.log` (override with `-LogFile`) so results can be shared
without copy-pasting the console.

```powershell
.\smoketest.ps1 -Build                 # build, then run every check
.\smoketest.ps1                        # run against already-built binaries
.\smoketest.ps1 -TcpPort 9001 -UdpPort 9002 -SkipAsm
.\smoketest.ps1 -LogFile run1.log      # write the transcript elsewhere
```

## Releases

Pre-built binaries are published on the
[Releases](https://github.com/kj299/net-listen/releases) page. To cut a new
one, push a version tag — the `Release` workflow builds on both platforms and
attaches the artifacts:

```
git tag v1.0.0
git push origin v1.0.0
```

This produces `net-listen-windows-x64.zip` (`c_listener.exe` +
`asm_listener.exe`) and `net-listen-linux-x64.tar.gz` (`c_listener`).
