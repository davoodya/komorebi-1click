# =====================================================================
# demo-stream.ps1  —  Deliberately chatty, long-running, SAFE fixture
#
# WHY THIS EXISTS
#   Ticket 11 requires proof that the Dashboard stays responsive while a
#   script streams output. "It should be fine" is not evidence, so this
#   script produces a controllable amount of chatter on BOTH stdout and
#   stderr over a controllable period, which lets the test suite verify
#   streaming, batching, cancellation and timeout against real output.
#
#   It touches NOTHING. No processes are read or killed, no scheduled task is
#   queried, no config is read. It is pure console output, so running it can
#   never disturb a live komorebi / whkd / yasb stack. That matters: every
#   other script in this folder operates on the real system.
#
# Usage:
#   pwsh -File demo-stream.ps1 -Lines 400 -DelayMs 0
#   pwsh -File demo-stream.ps1 -Lines 100000 -DelayMs 50 -TimeoutSeconds 3
#
#   -Lines         how many numbered lines to emit (default 50)
#   -DelayMs       pause between lines, which is what makes it "long-running"
#   -StdErrEvery   also write a line to stderr every Nth line (default 10).
#                  Both streams must be drained or the child blocks on a full
#                  pipe buffer — that is the deadlock this fixture reproduces
#                  on demand.
#   -TimeoutSeconds accepted for symmetry with the dashboard's own timeout
#                  option; this script does not enforce it itself. The
#                  CALLER enforces it, which is the behaviour under test.
#   -FailWith      exit with this code after finishing (to test failure paths)
# =====================================================================
[CmdletBinding()]
param(
    [int]    $Lines          = 50,
    [int]    $DelayMs        = 100,
    [int]    $StdErrEvery    = 10,
    [int]    $TimeoutSeconds = 0,
    [int]    $FailWith       = 0
)

$ErrorActionPreference = 'Continue'

Write-Host ("[demo-stream] starting: lines={0} delayMs={1} stderrEvery={2}" -f $Lines, $DelayMs, $StdErrEvery)
Write-Host ("[demo-stream] pid={0} powershell={1}" -f $PID, $PSVersionTable.PSVersion)
if ($TimeoutSeconds -gt 0) {
    Write-Host ("[demo-stream] caller asked for a {0}s budget" -f $TimeoutSeconds)
}

$started = [System.Diagnostics.Stopwatch]::StartNew()
$emitted = 0

for ($i = 1; $i -le $Lines; $i++) {
    Write-Host ("[demo-stream] line {0}/{1} elapsed={2:0.000}s" -f $i, $Lines, $started.Elapsed.TotalSeconds)

    # Interleave stderr so the suite proves BOTH redirected streams are read.
    # A reader that only drains stdout would stall here once stderr's pipe
    # buffer fills.
    if ($StdErrEvery -gt 0 -and ($i % $StdErrEvery -eq 0)) {
        [Console]::Error.WriteLine("[demo-stream] stderr checkpoint at line $i")
    }

    $emitted++
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

$started.Stop()
Write-Host ("[demo-stream] done: emitted={0} in {1:0.000}s" -f $emitted, $started.Elapsed.TotalSeconds)

if ($FailWith -ne 0) {
    [Console]::Error.WriteLine("[demo-stream] failing on purpose with code $FailWith")
    Write-Host ("[demo-stream] exiting with {0}" -f $FailWith)
    exit $FailWith
}

exit 0