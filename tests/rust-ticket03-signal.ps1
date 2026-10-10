# Ticket 03 / US 55 - the real delivery path for a console control event.
#
# Node cannot deliver a console control event on Windows, which is what made
# the old SKIP honest but unrunnable: process.kill(-pid, 'SIGBREAK') throws
# ESRCH (no negative-pid process-group semantics) and SIGBREAK is ENOSYS, and
# detached: true is DETACHED_PROCESS (no console at all), not
# CREATE_NEW_PROCESS_GROUP. The real Win32 path is:
#
#   1. CreateProcess with CREATE_NEW_PROCESS_GROUP, bInheritHandles, stdout
#      and stderr redirected to files, NOT hiding the console so the child
#      inherits the caller's real console (the delivery medium).
#   2. GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, childPid).
#   3. WaitForSingleObject to observe whether the child actually exited.
#
# The caller's console is gate-checked first with GetConsoleWindow: a
# pseudo-console (ConPTY, agent sessions, some CI) exposes no console window
# and cannot deliver console control events at all, so the caller must SKIP
# there instead of pretending the signal was sent.
#
# Modes:
#   -Gate                     print { consoleWindow } as JSON for the host gate.
#   -Run (default)            spawn, signal, wait, and write the result JSON.
#
# Output contract (Run mode), written to -ResultJsonPath:
#   { ok, pid, createError, aliveBefore, generateOk, generateLastError,
#     waitStatus, exitCode, signalAfterMs, exitTimeoutMs }
#   waitStatus 0 = WAIT_OBJECT_0 (observed exit); 258 = WAIT_TIMEOUT.
param(
  [string]$ExePath,
  [string[]]$Arguments = @(),
  [string]$ArgumentsFile,
  [int]$SignalAfterMs = 2500,
  [int]$ExitTimeoutMs = 20000,
  [string]$StdoutPath,
  [string]$StderrPath,
  [string]$ResultJsonPath,
  [switch]$Gate
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Write-Json([hashtable]$Data) {
  # Compact JSON on ONE line: the caller reads it back with node, where a
  # multi-line string would have to be re-assembled. The FILE is the contract
  # (the harness reads $ResultJsonPath); stdout is the human/probe view. A
  # missing file was the difference between an honest FAIL and a fake SKIP, so
  # both are always written when a path is given.
  $text = ($Data | ConvertTo-Json -Compress -Depth 4)
  $text | Write-Output
  if ($ResultJsonPath) {
    [System.IO.File]::WriteAllText($ResultJsonPath, $text, (New-Object System.Text.UTF8Encoding($false)))
  }
}

# === NATIVE BRIDGE ===

if (-not ('Win32Signal.Native' -as [type])) {
  Add-Type -Namespace 'Win32Signal' -Name 'Native' -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct SECURITY_ATTRIBUTES {
  public int nLength;
  public IntPtr lpSecurityDescriptor;
  public int bInheritHandle;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct STARTUPINFO {
  public int cb;
  public string lpReserved;
  public string lpDesktop;
  public string lpTitle;
  public int dwX;
  public int dwY;
  public int dwXSize;
  public int dwYSize;
  public int dwXCountChars;
  public int dwYCountChars;
  public int dwFillAttribute;
  public int dwFlags;
  public short wShowWindow;
  public short cbReserved2;
  public IntPtr lpReserved2;
  public IntPtr hStdInput;
  public IntPtr hStdOutput;
  public IntPtr hStdError;
}

[StructLayout(LayoutKind.Sequential)]
public struct PROCESS_INFORMATION {
  public IntPtr hProcess;
  public IntPtr hThread;
  public int dwProcessId;
  public int dwThreadId;
}

public const uint CREATE_NEW_PROCESS_GROUP = 0x00000200;
public const int STARTF_USESTDHANDLES = 0x00000100;
public const int STARTF_USESHOWWINDOW = 0x00000001;
public const short SW_HIDE = 0;
public const uint CTRL_BREAK_EVENT = 1;
public const uint WAIT_TIMEOUT = 0x00000102;

[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool CreateProcessW(
  string lpApplicationName,
  string lpCommandLine,
  IntPtr lpProcessAttributes,
  IntPtr lpThreadAttributes,
  [MarshalAs(UnmanagedType.Bool)] bool bInheritHandle,
  uint dwCreationFlags,
  IntPtr lpEnvironment,
  string lpCurrentDirectory,
  [In] ref STARTUPINFO lpStartupInfo,
  out PROCESS_INFORMATION lpProcessInformation);

[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr CreateFileW(
  string lpFileName,
  uint dwDesiredAccess,
  uint dwShareMode,
  [In] ref SECURITY_ATTRIBUTES lpSecurityAttributes,
  uint dwCreationDisposition,
  uint dwFlagsAndAttributes,
  IntPtr hTemplateFile);

[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GenerateConsoleCtrlEvent(uint dwCtrlEvent, uint dwProcessGroupId);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetExitCodeProcess(IntPtr hHandle, out int lpExitCode);

[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool CloseHandle(IntPtr hHandle);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetConsoleWindow();
'@
}
# === GATE / RUN ===

$json = @{ ok = $false }

# Host gate + argv: node can't hand an array through a command line, so args
# travel as JSON in a file; -Arguments keeps direct PowerShell invocations simple.
$argList = @()
if ($ArgumentsFile -and (Test-Path -LiteralPath $ArgumentsFile)) {
  $argList = @((Get-Content -LiteralPath $ArgumentsFile -Raw) | ConvertFrom-Json)
}
if ($Arguments -and $Arguments.Count -gt 0) { $argList = $Arguments }

# ---- Host gate: does the caller even have a console to deliver into? ----
$consoleWindow = [Win32Signal.Native]::GetConsoleWindow()
if ($Gate) {
  [ordered]@{ consoleWindow = [int64]$consoleWindow } | ConvertTo-Json -Compress | Write-Output
  if ($consoleWindow -eq [IntPtr]::Zero) { exit 10 }
  exit 0
}
$json.consoleWindow = [int64]$consoleWindow

if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) {
  $json.createError = "exe not found: $ExePath"
  Write-Json $json
  exit 2
}
if (-not $StdoutPath -or -not $StderrPath -or -not $ResultJsonPath) {
  $json.createError = 'StdoutPath, StderrPath and ResultJsonPath are required in Run mode'
  Write-Json $json
  exit 2
}

# ---- Redirection files, opened inheritable so the child keeps them ----
$GENERIC_WRITE = [uint32]0x40000000
$FILE_SHARE_READ = [uint32]1
$FILE_SHARE_WRITE = [uint32]2
$CREATE_ALWAYS = [uint32]2
$INVALID_HANDLE_VALUE = [int64]-1

function Open-Inheritable([string]$Path) {
  $sa = New-Object -TypeName 'Win32Signal.Native+SECURITY_ATTRIBUTES'
  $sa.nLength = [System.Runtime.InteropServices.Marshal]::SizeOf($sa)
  $sa.bInheritHandle = 1
  $handle = [Win32Signal.Native]::CreateFileW(
    $Path, $GENERIC_WRITE, ($FILE_SHARE_READ -bor $FILE_SHARE_WRITE), [ref]$sa, $CREATE_ALWAYS, 0, [IntPtr]::Zero)
  if ($handle -eq [IntPtr]::Zero -or [int64]$handle -eq $INVALID_HANDLE_VALUE) {
    throw "CreateFileW failed for ${Path}: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
  }
  return $handle
}

$hOut = Open-Inheritable $StdoutPath
$hErr = Open-Inheritable $StderrPath

# ---- Spawn: NEW process group (so the pid IS the group id), console shared ----
$si = New-Object -TypeName 'Win32Signal.Native+STARTUPINFO'
$si.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($si)
$si.dwFlags = [Win32Signal.Native]::STARTF_USESTDHANDLES -bor [Win32Signal.Native]::STARTF_USESHOWWINDOW
$si.wShowWindow = [Win32Signal.Native]::SW_HIDE
$si.hStdOutput = $hOut
$si.hStdError = $hErr

$quoted = @()
foreach ($a in $argList) {
  if ("$a" -match '\s') { $quoted += '"' + $a + '"' } else { $quoted += "$a" }
}
$commandLine = '"' + $ExePath + '"' + $(if ($quoted.Count -gt 0) { ' ' + ($quoted -join ' ') } else { '' })
$workdir = Split-Path -Path $ExePath -Parent

$pi = New-Object -TypeName 'Win32Signal.Native+PROCESS_INFORMATION'
$created = [Win32Signal.Native]::CreateProcessW(
  $ExePath, $commandLine, [IntPtr]::Zero, [IntPtr]::Zero, $true,
  [Win32Signal.Native]::CREATE_NEW_PROCESS_GROUP, [IntPtr]::Zero, $workdir, [ref]$si, [ref]$pi)

if (-not $created) {
  $json.createError = "CreateProcessW failed: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
  Write-Json $json
  exit 3
}
$json.ok = $true
$json.pid = $pi.dwProcessId
[void][Win32Signal.Native]::CloseHandle($pi.hThread)

$aliveStatus = [Win32Signal.Native]::WaitForSingleObject($pi.hProcess, 0)
$json.aliveBefore = ($aliveStatus -ne 0)

# ---- The interrupt itself ----
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt $SignalAfterMs) { Start-Sleep -Milliseconds 50 }
$json.signalAfterMs = $SignalAfterMs

$generateOk = [Win32Signal.Native]::GenerateConsoleCtrlEvent(
  [Win32Signal.Native]::CTRL_BREAK_EVENT, [uint32]$pi.dwProcessId)
$json.generateOk = $generateOk
if (-not $generateOk) {
  $json.generateLastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
}

# ---- Observe: did the child actually accept it? ----
$waitStatus = [Win32Signal.Native]::WaitForSingleObject($pi.hProcess, [uint32]$ExitTimeoutMs)
$json.waitStatus = $waitStatus
$exitCode = -1
if ($waitStatus -eq 0) {
  [void][Win32Signal.Native]::GetExitCodeProcess($pi.hProcess, [ref]$exitCode)
  $json.exitCode = $exitCode
}
$json.exitTimeoutMs = $ExitTimeoutMs

[void][Win32Signal.Native]::CloseHandle($pi.hProcess)
[void][Win32Signal.Native]::CloseHandle($hOut)
[void][Win32Signal.Native]::CloseHandle($hErr)

Write-Json $json
exit 0

# === END ===
