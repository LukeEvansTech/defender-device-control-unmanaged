function Invoke-DefenderDcUsbTest {
<#
.SYNOPSIS
    End-to-end USB stick test driver for the Defender Device Control policy.

.DESCRIPTION
    Operator-facing test that brackets a manual USB stick write attempt with
    DC policy apply and rollback. Captures a transcript and reads back the
    last 2 minutes of Defender 1109/1110/1111 events (softened to
    informational on modern MDE builds where events route to Defender XDR
    Advanced Hunting only).

    Phases:
      1. Pre-flight: Defender and Sense state.
      2. Capture pre-state of DC policy.
      3. Apply DC at -StartMode.
      4. Verify static state.
      5. Operator interactive: replug stick, attempt write, observe result.
      6. Read event-log signal (best-effort; zero events is not a failure).
      7. Restore DC to pre-test state (unless -KeepDcApplied).

    Requires administrator elevation.

.PARAMETER Drive
    Drive letter of the USB stick to test, e.g. 'E' or 'E:'. A trailing
    colon is accepted and stripped automatically.

.PARAMETER StartMode
    DC mode to apply during the test. Default 'Audit' (safer first proof).
    'Enforce' blocks writes and fires deny events.

.PARAMETER KeepDcApplied
    Switch. If set, skip the final rollback and leave DC at -StartMode after
    the test completes. Default: rollback to whatever DC mode was active
    before the test began.

.EXAMPLE
    Invoke-DefenderDcUsbTest -Drive E:

    Run an Audit-mode USB test against E: drive.

.EXAMPLE
    Invoke-DefenderDcUsbTest -Drive E: -StartMode Enforce -KeepDcApplied

    Run an Enforce-mode test and leave Enforce active afterwards.

.OUTPUTS
    PSCustomObject with properties:
      Failures       - [int] count of failed checks across pre-flight and verification
      TranscriptPath - absolute path to the per-invocation transcript log
      StartMode      - the -StartMode value the test applied ('Audit' or 'Enforce')
      EventsCaptured - [int] Defender events 1109/1110/1111 captured in the test window (informational; modern MDE routes to XDR)
      PreTestMode    - DC mode read before -StartMode was applied (used for rollback)

.LINK
    https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/run-end-to-end-test/
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType('DefenderDeviceControlUnmanaged.UsbTestResult')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]:?$')]
        [string] $Drive,

        [Alias('Mode')]
        [ValidateSet('Audit','Enforce')]
        [string] $StartMode = 'Audit',

        [switch] $KeepDcApplied
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Continue'

    if (-not (Test-DcIsElevated)) {
        throw "Invoke-DefenderDcUsbTest: must be run from an elevated PowerShell."
    }

    # Normalise drive letter: 'E:' -> 'E', 'E' -> 'E'
    $driveLetter = $Drive.TrimEnd(':').ToUpper()
    $drivePath   = "$driveLetter`:"

    $transcript = Start-DcTranscript -CmdletName 'Invoke-DefenderDcUsbTest'

    $failures = 0
    $failureRef = [ref]$failures

    $preMode       = $null
    $eventsCaptured = 0

    try {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host " Invoke-DefenderDcUsbTest -- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host " Drive: $drivePath  StartMode: $StartMode  KeepDcApplied: $KeepDcApplied" -ForegroundColor Cyan
        Write-Host " Transcript: $transcript" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan

        # --- Phase 1: Pre-flight ---
        Write-Host ""
        Write-Host "[1/7] Pre-flight" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
        $defender = Get-DcComputerStatus
        Write-DcCheckResult 'Defender AM service enabled' { $defender.AMServiceEnabled } 'AMServiceEnabled must be True' $failureRef
        $sense = Get-Service -Name Sense -ErrorAction SilentlyContinue
        Write-DcCheckResult 'Sense service Running' { $sense -and $sense.Status -eq 'Running' } 'Sense must be Running' $failureRef

        # --- Phase 2: Capture pre-state of DC ---
        Write-Host ""
        Write-Host "[2/7] Capture pre-state of DC" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
        $preState = Get-DefenderDcPolicy
        $preMode  = $preState.Mode
        Write-Host "  Pre-test DC mode: $preMode" -ForegroundColor DarkGray

        if ($PSCmdlet.ShouldProcess($drivePath, "Run USB Device Control test in $StartMode mode")) {
            # --- Phase 3: Apply DC at StartMode ---
            Write-Host ""
            Write-Host "[3/7] Apply DC -Mode $StartMode" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
            Set-DefenderDcPolicy -Mode $StartMode

            # --- Phase 4: Verify static state ---
            Write-Host ""
            Write-Host "[4/7] Verify static state" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
            $verifyResult = Test-DefenderDcPolicy -ExpectMode $StartMode
            Write-DcCheckResult "Static verification passes for $StartMode" { $verifyResult } "Test-DefenderDcPolicy returned false" $failureRef

            # --- Phase 5: Operator interactive ---
            Write-Host ""
            Write-Host "[5/7] Operator interactive test" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "  Action required:" -ForegroundColor Yellow
            Write-Host "    1. Unplug the USB stick from $drivePath (if currently mounted)." -ForegroundColor Yellow
            Write-Host "    2. Plug it back in. Wait for the drive letter to appear." -ForegroundColor Yellow
            Write-Host "    3. Open a file from $drivePath (read should always work)." -ForegroundColor Yellow
            Write-Host "    4. Try to copy a file TO $drivePath." -ForegroundColor Yellow
            Write-Host "         Audit:   succeeds, telemetry recorded in Defender XDR." -ForegroundColor Yellow
            Write-Host "         Enforce: fails with 'The media is write protected'." -ForegroundColor Yellow
            Write-Host ""
            $startTime = Get-Date
            Read-Host "  Press ENTER when finished with the manual test"

            # --- Phase 6: Read event-log signal (best-effort) ---
            Write-Host ""
            Write-Host "[6/7] Defender event-log lookup (last 2 minutes)" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
            try {
                $events = @(Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' -MaxEvents 100 -ErrorAction SilentlyContinue |
                    Where-Object { $_.Id -in @(1109, 1110, 1111) } |
                    Where-Object { $_.TimeCreated -gt $startTime.AddMinutes(-2) })
                $eventsCaptured = $events.Count
                Write-Host "  Events 1109/1110/1111 captured: $eventsCaptured" -ForegroundColor DarkGray
                if ($eventsCaptured -eq 0) {
                    Write-Host "  (Modern MDE builds route DC events to Defender XDR Advanced Hunting only;" -ForegroundColor Yellow
                    Write-Host "   zero local events is informational, not a failure. Check security.microsoft.com" -ForegroundColor Yellow
                    Write-Host "   DeviceEvents | where ActionType == 'RemovableStoragePolicyTriggered' for evidence.)" -ForegroundColor Yellow
                } else {
                    $events | ForEach-Object { Write-Host "    $($_.TimeCreated)  Id=$($_.Id)" -ForegroundColor DarkGray }
                }
            } catch {
                Write-Host "  (Event log lookup failed: $($_.Exception.Message))" -ForegroundColor Yellow
            }

            # --- Phase 7: Restore (unless KeepDcApplied) ---
            Write-Host ""
            Write-Host "[7/7] Restore pre-test DC state" -ForegroundColor Cyan
            Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
            if ($KeepDcApplied) {
                Write-Host "  -KeepDcApplied set; leaving DC at $StartMode." -ForegroundColor Yellow
            } else {
                if ($null -eq $preMode -or $preMode -eq $StartMode) {
                    Write-Host "  Pre-test mode equals StartMode ($preMode); no rollback needed." -ForegroundColor DarkGray
                } else {
                    Write-Host "  Rolling back to $preMode." -ForegroundColor DarkGray
                    Set-DefenderDcPolicy -Mode $preMode
                }
            }
        } else {
            Write-Host "  Preview only; skipping policy apply, manual prompt, event lookup, and rollback." -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        if ($failureRef.Value -eq 0) {
            Write-Host " Invoke-DefenderDcUsbTest: ALL CHECKS PASSED" -ForegroundColor Green
        } else {
            Write-Host " Invoke-DefenderDcUsbTest: $($failureRef.Value) CHECKS FAILED" -ForegroundColor Red
        }
        Write-Host " Transcript: $transcript" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
    }
    finally {
        Stop-Transcript | Out-Null
    }

    [pscustomobject]@{
        PSTypeName     = 'DefenderDeviceControlUnmanaged.UsbTestResult'
        Failures       = $failureRef.Value
        TranscriptPath = $transcript
        StartMode      = $StartMode
        EventsCaptured = $eventsCaptured
        PreTestMode    = $preMode
    }
}
