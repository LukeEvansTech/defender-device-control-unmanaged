function Invoke-DefenderDcOnboarding {
<#
.SYNOPSIS
    Onboard this Windows host to Microsoft Defender for Endpoint using the
    per-tenant local-script deployment method.

.DESCRIPTION
    Wraps Microsoft's per-tenant onboarding .cmd with pre-flight checks,
    auto-detection of the onboarding ZIP in $env:USERPROFILE\Downloads\,
    extraction, elevated execution, and post-flight verification.

    Pre-flight: Defender AM service enabled, Sense service present, not
    already onboarded.
    Post-flight: Sense Running + Automatic, OnboardingState=1, OrgId
    populated.

    Requires administrator elevation. Captures a transcript under
    $env:LOCALAPPDATA\DefenderDeviceControlUnmanaged\.

.PARAMETER OnboardingScript
    Optional path to either the per-tenant ZIP (e.g.
    WindowsDefenderATPOnboardingPackage.zip) or the extracted
    WindowsDefenderATP*OnboardingScript.cmd. If not supplied, searches
    $env:USERPROFILE\Downloads\ for files matching
    '*WindowsDefenderATPOnboarding*.zip' and uses the newest match.

.PARAMETER PostFlightWaitSeconds
    Seconds to wait between the onboarding script exit and the post-flight
    checks. Defender service start and registry markers are async. Default 30.

.EXAMPLE
    Invoke-DefenderDcOnboarding

    Auto-detect the onboarding ZIP in Downloads and run it.

.EXAMPLE
    Invoke-DefenderDcOnboarding -OnboardingScript C:\onboard\WindowsDefenderATPOnboardingPackage.zip

    Explicitly pass the ZIP path.

.OUTPUTS
    PSCustomObject with properties:
      SenseStatus     - 'Running' / 'Stopped' / etc. from Get-Service -Name Sense, or $null
      SenseStartType  - 'Automatic' / 'Manual' / etc., or $null
      OnboardingState - 1 when onboarded, 0/null otherwise (HKLM WATP Status)
      OrgId           - tenant OrgId GUID string, or $null
      Failures        - [int] count of failed pre-flight and post-flight checks
      TranscriptPath  - absolute path to the per-invocation transcript log

.LINK
    https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/onboard-to-mde/
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType('DefenderDeviceControlUnmanaged.OnboardingResult')]
    param(
        [string] $OnboardingScript,

        [Alias('SkipPostFlightWait')]
        [int]    $PostFlightWaitSeconds = 30
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Continue'

    if (-not (Test-DcIsElevated)) {
        throw "Invoke-DefenderDcOnboarding: must be run from an elevated PowerShell."
    }

    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $transcript = Start-DcTranscript -CmdletName 'Invoke-DefenderDcOnboarding'

    $failures = 0
    $failureRef = [ref]$failures

    $senseAfter = $null
    $obsAfter = $null
    $orgId = $null
    $extractedTemp = $null

    try {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host " Invoke-DefenderDcOnboarding -- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host " Transcript: $transcript" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan

        Write-Host ""
        Write-Host "[1/4] Pre-flight checks" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray

        $defender = Get-DcComputerStatus
        Write-Host "  Defender AM engine: $($defender.AMEngineVersion)" -ForegroundColor DarkGray
        Write-Host "  Defender AM product: $($defender.AMProductVersion)" -ForegroundColor DarkGray
        Write-Host "  Tamper Protection: $($defender.IsTamperProtected)" -ForegroundColor DarkGray

        Write-DcCheckResult 'Defender AM service enabled' { $defender.AMServiceEnabled } 'AMServiceEnabled must be True' $failureRef

        $sense = Get-Service -Name Sense -ErrorAction SilentlyContinue
        Write-DcCheckResult 'Sense service is installed' { $null -ne $sense } 'Sense service must exist on the box' $failureRef

        $watpStatus = 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status'
        $currentOnboardingState = $null
        if (Test-Path -LiteralPath $watpStatus) {
            $obs = (Get-ItemProperty -LiteralPath $watpStatus -Name OnboardingState -ErrorAction SilentlyContinue).OnboardingState
            if ($null -ne $obs) { $currentOnboardingState = [int]$obs }
        }
        Write-Host "  Current OnboardingState: $currentOnboardingState" -ForegroundColor DarkGray

        $alreadyOnboarded = ($sense -and $sense.Status -eq 'Running' -and $currentOnboardingState -eq 1)
        if ($alreadyOnboarded) {
            throw "Box is already onboarded (Sense=Running, OnboardingState=1). Do not re-run onboarding; if you need to re-onboard, offboard first."
        }

        Write-Host ""
        Write-Host "[2/4] Locate onboarding script" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
        $cmdPath = $null

        $zipPath = $null
        if ($OnboardingScript) {
            if (-not (Test-Path -LiteralPath $OnboardingScript)) {
                throw "OnboardingScript path does not exist: $OnboardingScript"
            }
            if ($OnboardingScript.ToLower().EndsWith('.cmd')) {
                $cmdPath = (Resolve-Path -LiteralPath $OnboardingScript).Path
            } elseif ($OnboardingScript.ToLower().EndsWith('.zip')) {
                $zipPath = $OnboardingScript
            } else {
                throw "OnboardingScript must be a .zip or a .cmd file: $OnboardingScript"
            }
        } else {
            $downloads = Join-Path $env:USERPROFILE 'Downloads'
            $zips = @(Get-ChildItem -LiteralPath $downloads -Filter '*WindowsDefenderATPOnboarding*.zip' -ErrorAction SilentlyContinue)
            if ($zips.Count -eq 0) {
                throw "No onboarding ZIP found in $downloads matching *WindowsDefenderATPOnboarding*.zip. Download from security.microsoft.com (Settings -> Endpoints -> Onboarding -> Local Script) or pass -OnboardingScript explicitly."
            }
            $newest = $zips | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Write-Host "  Found ZIP: $($newest.FullName) ($($newest.LastWriteTime))" -ForegroundColor DarkGray
            $zipPath = $newest.FullName
        }

        if ($zipPath) {
            $extractedTemp = Join-Path $env:TEMP "mde-onboard-$ts"
            New-Item -ItemType Directory -Path $extractedTemp | Out-Null
            Expand-Archive -LiteralPath $zipPath -DestinationPath $extractedTemp -Force
            $found = Get-ChildItem -LiteralPath $extractedTemp -Filter 'WindowsDefenderATP*OnboardingScript.cmd' -Recurse | Select-Object -First 1
            if (-not $found) { throw "Extracted ZIP did not contain WindowsDefenderATP*OnboardingScript.cmd" }
            $cmdPath = $found.FullName
        }
        Write-Host "  Using script: $cmdPath" -ForegroundColor DarkGray

        Write-Host ""
        Write-Host "[3/4] Run onboarding script (elevated)" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
        $scriptExit = 0
        if ($PSCmdlet.ShouldProcess($cmdPath, 'Run MDE onboarding script (cmd.exe)')) {
            & cmd.exe /c "`"$cmdPath`""
            $scriptExit = $LASTEXITCODE
        }
        Write-Host "  Onboarding script exit code: $scriptExit" -ForegroundColor DarkGray
        if ($scriptExit -ne 0) {
            Write-Host "  Onboarding script returned non-zero. Proceeding to post-flight to capture actual state." -ForegroundColor Yellow
        }

        Write-Host "  Settling $PostFlightWaitSeconds seconds before post-flight checks..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $PostFlightWaitSeconds

        Write-Host ""
        Write-Host "[4/4] Post-flight verification" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
        $senseAfter = Get-Service -Name Sense -ErrorAction SilentlyContinue
        Write-DcCheckResult 'Sense.Status = Running' { $senseAfter -and $senseAfter.Status -eq 'Running' } 'Sense service did not reach Running state' $failureRef
        Write-DcCheckResult 'Sense.StartType = Automatic' { $senseAfter -and $senseAfter.StartType -eq 'Automatic' } 'Sense start type should be Automatic post-onboarding' $failureRef

        if (Test-Path -LiteralPath $watpStatus) {
            $obs = (Get-ItemProperty -LiteralPath $watpStatus -Name OnboardingState -ErrorAction SilentlyContinue).OnboardingState
            if ($null -ne $obs) { $obsAfter = [int]$obs }
        }
        Write-DcCheckResult 'OnboardingState = 1' { $obsAfter -eq 1 } "expected 1, got '$obsAfter'" $failureRef

        if (Test-Path -LiteralPath $watpStatus) {
            $orgId = (Get-ItemProperty -LiteralPath $watpStatus -Name OrgId -ErrorAction SilentlyContinue).OrgId
        }
        Write-DcCheckResult 'OrgId is populated' { -not [string]::IsNullOrEmpty($orgId) } 'OrgId must be a non-empty string' $failureRef

        Write-Host ""
        Write-Host "Final state:" -ForegroundColor Yellow
        Write-Host "  Sense.Status     : $(if ($senseAfter) { $senseAfter.Status } else { '(missing)' })" -ForegroundColor DarkGray
        Write-Host "  Sense.StartType  : $(if ($senseAfter) { $senseAfter.StartType } else { '(missing)' })" -ForegroundColor DarkGray
        Write-Host "  OnboardingState  : $obsAfter" -ForegroundColor DarkGray
        Write-Host "  OrgId            : $orgId" -ForegroundColor DarkGray

        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        if ($failureRef.Value -eq 0) {
            Write-Host " Invoke-DefenderDcOnboarding: ALL CHECKS PASSED" -ForegroundColor Green
        } else {
            Write-Host " Invoke-DefenderDcOnboarding: $($failureRef.Value) CHECKS FAILED" -ForegroundColor Red
        }
        Write-Host " Transcript: $transcript" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
    }
    finally {
        if ($extractedTemp -and (Test-Path -LiteralPath $extractedTemp)) {
            Remove-Item -LiteralPath $extractedTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
        Stop-Transcript | Out-Null
    }

    [pscustomobject]@{
        PSTypeName       = 'DefenderDeviceControlUnmanaged.OnboardingResult'
        SenseStatus      = if ($senseAfter) { $senseAfter.Status }    else { $null }
        SenseStartType   = if ($senseAfter) { $senseAfter.StartType } else { $null }
        OnboardingState  = $obsAfter
        OrgId            = $orgId
        Failures         = $failureRef.Value
        TranscriptPath   = $transcript
    }
}
