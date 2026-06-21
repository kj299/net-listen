<#
.SYNOPSIS
    Smoke test for net-listen on Windows. Iterates across the tool's
    capabilities and validates that it behaves as expected.

.DESCRIPTION
    Exercises, in order:
      1. Argument validation  - usage message and exit codes for bad input
      2. TCP listener         - bind, accept, receive, client-close reporting
      3. UDP listener         - bind, receive datagram
      4. select() multiplex   - both protocols served by one running instance
      5. Graceful shutdown    - Ctrl+C path (best effort on Windows)
      6. asm_listener.exe      - Windows-only TCP echo (optional)

    Each check prints [PASS] / [FAIL] / [WARN]. The script exits with a code
    equal to the number of failures (0 = all good), so it can gate CI or a
    pre-commit hook.

.PARAMETER TcpPort
    TCP port for c_listener (default 54321).

.PARAMETER UdpPort
    UDP port for c_listener (default 54322).

.PARAMETER Build
    Build the binaries with mingw32-make before testing.

.PARAMETER SkipAsm
    Skip the asm_listener.exe checks.

.PARAMETER LogFile
    Path of the transcript log to write (default: smoketest.log next to this
    script). The full console output is captured there each run so it can be
    shared without copy-pasting.

.EXAMPLE
    .\smoketest.ps1 -Build

.EXAMPLE
    .\smoketest.ps1 -TcpPort 9001 -UdpPort 9002 -SkipAsm
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)] [int]$TcpPort = 54321,
    [ValidateRange(1, 65535)] [int]$UdpPort = 54322,
    [switch]$Build,
    [switch]$SkipAsm,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

# ---- tiny test harness -------------------------------------------------
$script:Pass = 0; $script:Fail = 0; $script:Warn = 0
function Pass($m)    { Write-Host "  [PASS] $m" -ForegroundColor Green;  $script:Pass++ }
function Fail($m)    { Write-Host "  [FAIL] $m" -ForegroundColor Red;    $script:Fail++ }
function WarnMsg($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow; $script:Warn++ }
function Section($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Check([string]$desc, [bool]$cond) { if ($cond) { Pass $desc } else { Fail $desc } }

# Read a file that another process may still have open for writing.
function Read-Shared([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try { (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}

# ---- client helpers ----------------------------------------------------
function Send-Tcp([int]$Port, [string]$Msg) {
    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect('127.0.0.1', $Port)
    $stream = $c.GetStream()
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Msg)
    $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
    Start-Sleep -Milliseconds 250
    $c.Close()
}

function Send-Udp([int]$Port, [string]$Msg) {
    $u = New-Object System.Net.Sockets.UdpClient
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Msg)
    [void]$u.Send($bytes, $bytes.Length, '127.0.0.1', $Port)
    $u.Close()
}

# ---- process helpers ---------------------------------------------------
function Start-Listener([string]$Exe, [string[]]$ProcArgs) {
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    # Start-Process rejects an empty -ArgumentList, so omit it for arg-less exes.
    if ($ProcArgs.Count -eq 0) {
        $p = Start-Process -FilePath $Exe -PassThru -WindowStyle Hidden `
                -RedirectStandardOutput $out -RedirectStandardError $err
    } else {
        $p = Start-Process -FilePath $Exe -ArgumentList $ProcArgs -PassThru -WindowStyle Hidden `
                -RedirectStandardOutput $out -RedirectStandardError $err
    }
    [pscustomobject]@{ Proc = $p; Out = $out; Err = $err }
}

function Stop-Listener($L, [switch]$Keep) {
    if ($L.Proc -and -not $L.Proc.HasExited) {
        Stop-Process -Id $L.Proc.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 150
    if (-not $Keep) { Remove-Item -LiteralPath $L.Out, $L.Err -ErrorAction SilentlyContinue }
}

# Run the exe to completion (for the fast-exit argument-validation cases).
function Invoke-Exit([string[]]$ProcArgs) {
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    if ($ProcArgs.Count -eq 0) {
        $p = Start-Process -FilePath $cExe -PassThru -Wait -WindowStyle Hidden `
                -RedirectStandardOutput $out -RedirectStandardError $err
    } else {
        $p = Start-Process -FilePath $cExe -ArgumentList $ProcArgs -PassThru -Wait -WindowStyle Hidden `
                -RedirectStandardOutput $out -RedirectStandardError $err
    }
    $result = [pscustomobject]@{
        Code = $p.ExitCode
        Out  = Read-Shared $out
        Err  = Read-Shared $err
    }
    Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue
    $result
}

function Test-TcpPortFree([int]$Port) {
    -not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

# ---- logging -----------------------------------------------------------
# Capture the whole run (including the build step and any errors) to a file
# so results can be shared without copy-pasting the console.
if (-not $LogFile) { $LogFile = Join-Path $PSScriptRoot 'smoketest.log' }
try { Stop-Transcript | Out-Null } catch { }   # clear any stale transcript
$script:Transcribing = $false
try {
    Start-Transcript -Path $LogFile -Force | Out-Null
    $script:Transcribing = $true
} catch {
    Write-Host "warning: could not start transcript ($_)" -ForegroundColor Yellow
}

# Print the summary, stop the transcript, and exit with the given code. All
# exits go through here so the log is always closed cleanly.
function Finish([int]$Code) {
    Write-Host ""
    Write-Host ("=" * 40)
    Write-Host ("Result: {0} passed, {1} failed, {2} warnings" -f $script:Pass, $script:Fail, $script:Warn) `
        -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
    if ($script:Transcribing) {
        try { Stop-Transcript | Out-Null } catch { }
        $script:Transcribing = $false
    }
    Write-Host "Full log written to: $LogFile" -ForegroundColor White
    exit $Code
}

# Any unhandled terminating error still closes the log and exits non-zero.
trap { Write-Host "UNEXPECTED ERROR: $($_ | Out-String)" -ForegroundColor Red; Finish 1 }

# ========================================================================
Write-Host "net-listen smoke test" -ForegroundColor White
Write-Host "tcp/$TcpPort  udp/$UdpPort  (cwd: $PSScriptRoot)"

if ($Build) {
    Section "Build"
    & mingw32-make 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { Fail "mingw32-make"; Finish 1 }
    Pass "mingw32-make"
}

$cExe   = Join-Path $PSScriptRoot 'c_listener.exe'
$asmExe = Join-Path $PSScriptRoot 'asm_listener.exe'
if (-not (Test-Path -LiteralPath $cExe)) {
    Write-Host "c_listener.exe not found - build first (e.g. .\smoketest.ps1 -Build)" -ForegroundColor Red
    Finish 1
}
if (-not (Test-TcpPortFree $TcpPort)) {
    Write-Host "TCP/$TcpPort is already in use - choose another with -TcpPort" -ForegroundColor Red
    Finish 1
}

# ---- 1. argument validation -------------------------------------------
Section "1. Argument validation"
$r = Invoke-Exit @()
Check "no args -> exit 1"                  ($r.Code -eq 1)
Check "no args -> prints usage to stderr"  ($r.Err -match 'Usage:')

$r = Invoke-Exit @('123')
Check "one arg -> exit 1"                  ($r.Code -eq 1)
Check "one arg -> prints usage"            ($r.Err -match 'Usage:')

$r = Invoke-Exit @('abc', '5678')
Check "non-numeric port -> exit 1"         ($r.Code -eq 1)
Check "non-numeric port -> error message"  ($r.Err -match 'integers in 1\.\.65535')

$r = Invoke-Exit @('0', '5678')
Check "port 0 rejected -> exit 1"          ($r.Code -eq 1)

$r = Invoke-Exit @('70000', '5678')
Check "port > 65535 rejected -> exit 1"    ($r.Code -eq 1)

# ---- 2-4. TCP, UDP and select() multiplexing --------------------------
Section "2-4. TCP + UDP listeners (select multiplexing)"
$L = Start-Listener $cExe @("$TcpPort", "$UdpPort")
try {
    Start-Sleep -Milliseconds 700
    Check "process is running after bind" (-not $L.Proc.HasExited)

    $banner = Read-Shared $L.Out
    Check "prints listening banner" ($banner -match "listening: tcp/$TcpPort udp/$UdpPort")

    Check "TCP socket is in LISTEN state" `
        ([bool](Get-NetTCPConnection -LocalPort $TcpPort -State Listen -ErrorAction SilentlyContinue))
    Check "UDP socket is bound" `
        ([bool](Get-NetUDPEndpoint -LocalPort $UdpPort -ErrorAction SilentlyContinue))

    # TCP capability
    $tcpMsg = 'hello-tcp'
    Send-Tcp $TcpPort $tcpMsg
    Start-Sleep -Milliseconds 400
    $o = Read-Shared $L.Out
    Check "TCP: logs incoming connection" ($o -match '\[tcp\] connection from 127\.0\.0\.1:')
    Check "TCP: echoes received payload"  ($o -match "\[tcp\].*$tcpMsg")
    Check "TCP: reports client close"     ($o -match '\[tcp\] 127\.0\.0\.1:\d+ closed')

    # UDP capability (same instance -> proves select() serves both)
    $udpMsg = 'hello-udp'
    Send-Udp $UdpPort $udpMsg
    Start-Sleep -Milliseconds 400
    $o = Read-Shared $L.Out
    Check "UDP: receives datagram"        ($o -match '\[udp\] 127\.0\.0\.1:')
    Check "UDP: shows payload"            ($o -match "\[udp\].*$udpMsg")
    Check "multiplex: TCP+UDP both served by one instance" `
        (($o -match "\[tcp\].*$tcpMsg") -and ($o -match "\[udp\].*$udpMsg"))
}
finally {
    Stop-Listener $L
}

# ---- 5. graceful shutdown (best effort) -------------------------------
Section "5. Graceful Ctrl+C shutdown (best effort)"
# A true CTRL_C_EVENT is awkward to deliver to a hidden child on Windows;
# `taskkill` without /F posts a console-close event that the program's
# SetConsoleCtrlHandler should catch and turn into a clean "shutting down".
$L = Start-Listener $cExe @("$TcpPort", "$UdpPort")
try {
    Start-Sleep -Milliseconds 600
    taskkill /PID $L.Proc.Id 2>&1 | Out-Null
    $exited = $L.Proc.WaitForExit(5000)
    $o = Read-Shared $L.Out
    if ($exited -and $o -match 'shutting down') {
        Pass "received close event and shut down cleanly"
    } elseif ($exited) {
        WarnMsg "process exited but did not log 'shutting down' (console-signal timing)"
    } else {
        WarnMsg "process did not respond to close event in time (Windows signal limitation)"
    }
}
finally {
    Stop-Listener $L
}

# ---- 6. asm_listener.exe ----------------------------------------------
if (-not $SkipAsm) {
    Section "6. asm_listener.exe (TCP/1234 echo)"
    if (-not (Test-Path -LiteralPath $asmExe)) {
        WarnMsg "asm_listener.exe not found - skipping (build with NASM, or pass -SkipAsm)"
    } elseif (-not (Test-TcpPortFree 1234)) {
        WarnMsg "TCP/1234 already in use - skipping asm test"
    } else {
        $A = Start-Listener $asmExe @()
        try {
            Start-Sleep -Milliseconds 600
            Check "asm: process running after bind" (-not $A.Proc.HasExited)
            Check "asm: TCP/1234 in LISTEN state" `
                ([bool](Get-NetTCPConnection -LocalPort 1234 -State Listen -ErrorAction SilentlyContinue))
            $banner = Read-Shared $A.Out
            Check "asm: prints listening banner" ($banner -match 'listening on TCP/1234')

            $asmMsg = 'asm-ping'
            Send-Tcp 1234 $asmMsg
            Start-Sleep -Milliseconds 400
            $o = Read-Shared $A.Out
            Check "asm: logs accepted connection" ($o -match 'connection accepted')
            Check "asm: echoes received bytes"    ($o -match $asmMsg)
        }
        finally {
            Stop-Listener $A
        }
    }
} else {
    Section "6. asm_listener.exe"
    WarnMsg "skipped (-SkipAsm)"
}

# ---- summary -----------------------------------------------------------
Finish $script:Fail
