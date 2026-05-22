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

    try {
        if (& $Test) {
            Write-Host "  PASS  $Name" -ForegroundColor Green
        } else {
            Write-Host "  FAIL  $Name  ($ExpectedMsg)" -ForegroundColor Red
            $FailureCounter.Value++
        }
    } catch {
        Write-Host "  FAIL  $Name  (threw: $($_.Exception.Message))" -ForegroundColor Red
        $FailureCounter.Value++
    }
}
