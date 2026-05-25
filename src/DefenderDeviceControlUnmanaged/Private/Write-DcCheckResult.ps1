function Write-DcCheckResult {
<#
.SYNOPSIS
    Run a verification check and report PASS/FAIL on the host.

.DESCRIPTION
    Operator-facing assertion helper used by Test-DefenderDcPolicy,
    Invoke-DefenderDcOnboarding, and Invoke-DefenderDcUsbTest. Executes
    the supplied Test scriptblock; prints "PASS  <Name>" in green on a
    truthy result, or "FAIL  <Name>  (<ExpectedMsg>)" in red on a falsy
    result or thrown exception. Increments the caller's failure counter
    on FAIL via a [ref] parameter.

    Also writes a structured per-check record to the Information stream
    (PSCustomObject with Result/Name/ExpectedMsg/Error) tagged with the
    'DcCheck' Information tag, so scripted callers can capture results
    via -InformationVariable or 6>&1 without losing the colored host UX.

.PARAMETER Name
    Human-readable description of the check.

.PARAMETER Test
    Scriptblock evaluated for truthiness. Bound to the caller's scope.

.PARAMETER ExpectedMsg
    Hint shown on FAIL describing what should have been true.

.PARAMETER FailureCounter
    [ref]-wrapped integer counter incremented on FAIL.
#>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [scriptblock] $Test,

        [Parameter(Mandatory)]
        [string] $ExpectedMsg,

        [Parameter(Mandatory)]
        [ref] $FailureCounter
    )

    $result      = 'FAIL'
    $errorDetail = $null
    try {
        if (& $Test) {
            $result = 'PASS'
            Write-Host "  PASS  $Name" -ForegroundColor Green
        } else {
            Write-Host "  FAIL  $Name  ($ExpectedMsg)" -ForegroundColor Red
            $FailureCounter.Value++
        }
    } catch {
        $errorDetail = $_.Exception.Message
        Write-Host "  FAIL  $Name  (threw: $errorDetail)" -ForegroundColor Red
        $FailureCounter.Value++
    }

    Write-Information ([pscustomobject]@{
        Result      = $result
        Name        = $Name
        ExpectedMsg = $ExpectedMsg
        Error       = $errorDetail
    }) -Tags 'DcCheck'
}
