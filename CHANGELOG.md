# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Release tags are named `vMAJOR.MINOR.PATCH` (for example `v0.1.2`). The
`Release` workflow only triggers on tags matching `v*`, so a tag without the
`v` prefix builds nothing and publishes nothing.

## [Unreleased]

### Added

- **Configurable bind address.** `c_listener` takes an optional third
  argument, the IPv4 address to bind: `c_listener <tcp-port> <udp-port>
  [bind-address]`. It defaults to `0.0.0.0`, so existing two-argument
  invocations are unchanged. Passing `127.0.0.1` restricts the listener to
  connections originating on the same machine, which previously was not
  possible — the README could only warn that the tool was reachable from
  anywhere that could route to the host.

  The address must be an IPv4 literal; hostnames are not resolved. An
  unparseable address is rejected before any socket is created. The assembly
  listener is unchanged and still binds all interfaces.

## [v0.1.3] — 2026-09-19

### Security

- **Third-party GitHub Actions are pinned to exact commit SHAs** rather than
  mutable version tags. A tag can be repointed by whoever controls the action's
  repository, and the release workflow runs with `contents: write`, so a moved
  tag could have tampered with published releases. Each pin carries its version
  as a trailing comment.

### Changed

- Upgraded the pinned actions, three of which were majors behind:
  `actions/checkout` v5 → v7.0.1, `actions/upload-artifact` v4 → v7.0.1, and
  `softprops/action-gh-release` v2 → v3.0.3. All three move the action runtime
  to Node 24. `ilammy/setup-nasm` was already on its latest major and is pinned
  at v1.5.2.

  Note that `setup-nasm` still runs on Node 20, so GitHub's Node 20 deprecation
  warning will continue to appear until upstream publishes a Node 24 build — it
  just no longer also names `upload-artifact`.


## [v0.1.2] — 2026-09-13

### Fixed

- **Clean shutdown when the console window is closed.** Windows terminates a
  process as soon as its console handler returns from `CTRL_CLOSE_EVENT`, so
  `main` was being killed before it could write `shutting down` or close its
  sockets. The handler now sets the stop flag and waits (bounded, inside the
  grace window) on an event that `main` signals after cleanup. `CTRL_C_EVENT`
  and `CTRL_BREAK_EVENT` return immediately, since they do not terminate the
  process.

### Added

- **ASan/UBSan CI job.** Builds with `-fsanitize=address,undefined`, drives the
  listener through `tools/exercise.py`, fails on any sanitizer finding, and
  uploads the log as an artifact. Covers memory safety on the paths handling
  untrusted network input, which the behavioural smoke test cannot see.
- `tools/exercise.py` — load driver covering zero-length and oversized
  datagrams, 45 concurrent TCP clients with interleaved closes and late
  joiners, an abrupt RST disconnect, and hostile byte payloads.

## [v0.1.1] — 2026-07-02

### Security

- **Received bytes are sanitized before printing.** Non-printable bytes are
  replaced with `.`, so a remote peer can no longer inject terminal escape
  sequences into the operator's console, and embedded NULs no longer silently
  truncate the displayed payload.

### Fixed

- **`WriteFile` API-contract violation in the assembly listener.** Every call
  passed `lpNumberOfBytesWritten = NULL` together with `lpOverlapped = NULL`,
  which Win32 does not permit. A real output pointer is now supplied.
- **Spinning on `accept()` failure.** The assembly listener now backs off
  100 ms between retries instead of looping tightly and flooding stdout.
- **`MAX_CLIENTS` used Windows `fd_set` semantics on POSIX.** A Windows
  `fd_set` holds up to `FD_SETSIZE` sockets regardless of value, while POSIX
  `FD_SET()` is undefined for any descriptor *number* at or above
  `FD_SETSIZE`. The cap is now safe under either interpretation.
- The smoke test no longer stops a transcript the user started themselves.

### Changed

- **Releases are gated on tests.** The release workflow builds *and* smoke
  tests on both platforms before packaging, so a tag can no longer publish
  untested binaries.
- `actions/checkout` bumped to v5 in both workflows.
- README documents that the listeners bind `0.0.0.0` (all interfaces) and that
  output is sanitized.

## [v0.1.0] — 2026-06-21

First tagged release. The listeners were rewritten for portability and
robustness, and the build, test, and release pipeline was created from
scratch.

### Added

- **Cross-platform C listener.** Builds and runs on Ubuntu, Red Hat, and
  Windows from one source file, with the platform-specific socket details
  isolated in a shim.
- **True `select()` multiplexing.** A single event loop polls the UDP socket,
  the TCP listener, and every connected TCP client together, so multiple TCP
  clients are served concurrently and UDP is never starved while a client is
  connected.
- **OS-detecting `Makefile`.** Detects the host OS (and Linux distribution) and
  selects compiler flags, link libraries, and targets accordingly. The
  Windows-only assembly listener is built only on Windows, and only when NASM
  is present.
- **`smoketest.ps1`** — Windows capability suite covering argument validation,
  TCP and UDP receipt, multiplexing, graceful shutdown, and the assembly
  listener's echo. Writes a transcript to `smoketest.log`.
- **CI across three targets** — `ubuntu-latest`, a `redhat/ubi9` container, and
  `windows-latest`, the last running the full smoke suite and publishing the
  built binaries as artifacts.
- **`Release` workflow** — builds on Windows and Linux from a `v*` tag and
  attaches `net-listen-windows-x64.zip` and `net-listen-linux-x64.tar.gz` to
  the GitHub Release.
- `build.bat` for building on Windows without `make`, and a `.gitignore`.

### Fixed

- **CI ran none of its steps.** The original workflow was the default
  autotools template (`./configure`, `make`, `make check`, `make distcheck`)
  against a project with no configure script or `Makefile`, on a Linux runner,
  for Windows-only source. Replaced with a real build.
- **`make` invoked `cc`, which MinGW does not provide.** GNU Make pre-defines
  `CC` as `cc` and `?=` cannot override a built-in default, so the local
  Windows build failed with `CreateProcess ... failed`. `CC` is now overridden
  only when it is still the built-in default.
- **Unflushed output under redirection.** The `closed` and `shutting down`
  lines lacked the `fflush(stdout)` every other print had, so they stayed
  buffered until exit when stdout was redirected to a file.
- **Windows build failure** from `sig_atomic_t` being used without
  `<signal.h>` on the Windows path.
- **Stale Linux syscalls in the assembly listener.** `int 0x80` calls that
  never worked on Windows were replaced with a NASM Win64 implementation
  calling Winsock directly, following the Microsoft x64 ABI.
- Argument handling: ports are parsed with `strtol` and range-checked rather
  than `atoi`, and the unreachable `argc == 1` branch was removed.

### Removed

- The committed `c_listener.exe`, which was built from superseded source. CI
  and the release workflow now publish fresh binaries.

[Unreleased]: https://github.com/kj299/net-listen/compare/v0.1.3...HEAD
[v0.1.3]: https://github.com/kj299/net-listen/compare/v0.1.2...v0.1.3
[v0.1.2]: https://github.com/kj299/net-listen/compare/v0.1.1...v0.1.2
[v0.1.1]: https://github.com/kj299/net-listen/compare/v0.1.0...v0.1.1
[v0.1.0]: https://github.com/kj299/net-listen/releases/tag/v0.1.0
