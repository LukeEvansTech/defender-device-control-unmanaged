function Test-DcXmlWithMpCmdRun {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $XmlPath,

        [Parameter(Mandatory)]
        [ValidateSet('Groups','Rules')]
        [string] $Kind
    )

    $exe = Get-DcMpCmdRunPath
    if (-not $exe) {
        Write-Warning "  MpCmdRun.exe not found - skipping engine-side validation of $XmlPath."
        return
    }
    $arg = if ($Kind -eq 'Groups') { '-Groups' } else { '-Rules' }
    $output = & $exe -DeviceControl -TestPolicyXml $XmlPath $arg 2>&1
    $exit = $LASTEXITCODE
    $output | ForEach-Object { Write-Verbose "    $_" }
    if ($exit -ne 0) {
        throw "MpCmdRun -TestPolicyXml $arg returned $exit for $XmlPath - aborting before any registry writes."
    }
}
