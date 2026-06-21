@echo off
REM Build both net-listen binaries on Windows using MinGW-w64 + NASM.
REM
REM Requires gcc, ld, and nasm on PATH. The WinLibs distribution
REM (https://winlibs.com/) bundles all three. Install via winget:
REM   winget install -e --id BrechtSanders.WinLibs.POSIX.UCRT
REM
REM Usage: build.bat [clean]

setlocal enableextensions

if /I "%~1"=="clean" (
    if exist c_listener.exe   del /q c_listener.exe
    if exist asm_listener.exe del /q asm_listener.exe
    if exist net-listen.obj   del /q net-listen.obj
    echo cleaned
    exit /b 0
)

where gcc  >nul 2>&1 || (echo ERROR: gcc not found on PATH  & exit /b 1)
where nasm >nul 2>&1 || (echo ERROR: nasm not found on PATH & exit /b 1)

echo [1/3] compiling c_listener.exe
gcc -O2 -Wall -Wextra c_listener.c -o c_listener.exe -lws2_32 || exit /b 1

echo [2/3] assembling net-listen.obj
nasm -f win64 net-listen.asm -o net-listen.obj || exit /b 1

echo [3/3] linking asm_listener.exe
gcc -nostartfiles -Wl,-e,start net-listen.obj -o asm_listener.exe -lws2_32 -lkernel32 || exit /b 1

echo done: c_listener.exe asm_listener.exe
endlocal
