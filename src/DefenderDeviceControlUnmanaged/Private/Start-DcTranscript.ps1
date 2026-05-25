function Start-DcTranscript {
<#
.SYNOPSIS
    Start a per-invocation PowerShell transcript under the module's log dir.

.DESCRIPTION
    Ensures $env:LOCALAPPDATA\DefenderDeviceControlUnmanaged exists, computes a
    timestamped transcript filename for the calling cmdlet, and starts the
    transcript with -Force (silent). Returns the transcript path so the caller
    can record it on the result object and surface it in the closing summary.

.PARAMETER CmdletName
    Calling cmdlet name. Used in the transcript filename.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $CmdletName
    )

    $outputDir = Join-Path $env:LOCALAPPDATA 'DefenderDeviceControlUnmanaged'
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $transcript = Join-Path $outputDir "$CmdletName.$ts.transcript.txt"
    Start-Transcript -Path $transcript -Force | Out-Null
    return $transcript
}
