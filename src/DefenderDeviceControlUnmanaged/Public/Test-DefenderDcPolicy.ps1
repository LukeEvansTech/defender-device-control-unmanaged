function Test-DefenderDcPolicy {
<#
.SYNOPSIS
    Verify the Defender Device Control policy state on this machine.

.DESCRIPTION
    Reads registry + Defender engine state, prints PASS/FAIL per check,
    returns boolean (true if all checks passed). Prints a dynamic-test
    recipe the operator can drive with a real USB stick.

.PARAMETER ExpectMode
    Audit, Enforce, or Off. The state we expect to find. Default Audit.

.EXAMPLE
    Test-DefenderDcPolicy -ExpectMode Audit

    Verify policy is in Audit mode and the engine has consumed it.

.EXAMPLE
    Test-DefenderDcPolicy -ExpectMode Off

    Verify the policy has been fully removed.

.LINK
    https://lukeevanstech.github.io/defender-device-control-unmanaged/
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Alias('Mode')]
        [ValidateSet('Audit','Enforce','Off')]
        [string] $ExpectMode = 'Audit'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $failures = 0
    $failureRef = [ref]$failures

    Write-Host "Defender Device Control verification (ExpectMode=$ExpectMode)" -ForegroundColor Yellow

    $status = Get-DcComputerStatus
    Write-DcCheckResult 'Defender AM service enabled' { $status.AMServiceEnabled } 'AMServiceEnabled must be True' $failureRef
    Write-DcCheckResult 'Defender antivirus enabled'  { $status.AntivirusEnabled } 'AntivirusEnabled must be True' $failureRef

    if ($ExpectMode -eq 'Off') {
        Write-DcCheckResult 'Device Control root key absent' {
            -not (Test-Path -LiteralPath $script:DcRoot)
        } "$script:DcRoot should not exist" $failureRef

        $featProp = Get-ItemProperty -LiteralPath $script:DcFeatures -Name DeviceControlEnabled -ErrorAction SilentlyContinue
        Write-DcCheckResult 'Features\DeviceControlEnabled absent or 0' {
            $null -eq $featProp -or $featProp.DeviceControlEnabled -eq 0
        } 'Features\DeviceControlEnabled must be 0 or absent' $failureRef

        Write-DcCheckResult 'Engine reports DeviceControlState=Disabled' {
            $prop = $status.PSObject.Properties['DeviceControlState']
            $null -eq $prop -or $prop.Value -eq 'Disabled' -or $prop.Value -eq 0
        } 'engine view should reflect that DC is disabled' $failureRef

    } else {

        Write-DcCheckResult 'Features\DeviceControlEnabled = 1' {
            $p = Get-ItemProperty -LiteralPath $script:DcFeatures -Name DeviceControlEnabled -ErrorAction SilentlyContinue
            $null -ne $p -and $p.DeviceControlEnabled -eq 1
        } 'must be 1' $failureRef

        Write-DcCheckResult 'Device Control\DefaultEnforcement = 1 (Allow)' {
            $p = Get-ItemProperty -LiteralPath $script:DcRoot -Name DefaultEnforcement -ErrorAction SilentlyContinue
            $null -ne $p -and $p.DefaultEnforcement -eq 1
        } 'must be 1' $failureRef

        Write-DcCheckResult 'SecuredDevicesConfiguration scopes Removable + CdRom + Wpd' {
            $p = Get-ItemProperty -LiteralPath $script:DcRoot -Name SecuredDevicesConfiguration -ErrorAction SilentlyContinue
            $null -ne $p -and $p.SecuredDevicesConfiguration -eq 'RemovableMediaDevices|CdRomDevices|WpdDevices'
        } 'must be exactly "RemovableMediaDevices|CdRomDevices|WpdDevices"' $failureRef

        $groupsRegVal = $null
        $groupsRef = [ref]$groupsRegVal
        Write-DcCheckResult 'Policy Groups\PolicyGroups REG_SZ exists' {
            $p = Get-ItemProperty -LiteralPath $script:DcGroupsKey -Name PolicyGroups -ErrorAction SilentlyContinue
            $groupsRef.Value = if ($null -ne $p) { $p.PolicyGroups } else { $null }
            $null -ne $groupsRef.Value -and $groupsRef.Value -ne ''
        } 'must be a non-empty string' $failureRef

        Write-DcCheckResult 'Policy Groups XML file exists at registered path' {
            $null -ne $groupsRef.Value -and (Test-Path -LiteralPath $groupsRef.Value -PathType Leaf)
        } 'file at the registered path must exist' $failureRef

        Write-DcCheckResult 'Policy Groups XML parses as 3 Group records' {
            if ($null -eq $groupsRef.Value -or -not (Test-Path -LiteralPath $groupsRef.Value -PathType Leaf)) { return $false }
            @(Read-DcPolicyXml -Path $groupsRef.Value).Count -eq 3
        } 'must contain exactly 3 <Group> elements' $failureRef

        $rulesRegVal = $null
        $rulesRef = [ref]$rulesRegVal
        Write-DcCheckResult 'Policy Rules\PolicyRules REG_SZ exists' {
            $p = Get-ItemProperty -LiteralPath $script:DcRulesKey -Name PolicyRules -ErrorAction SilentlyContinue
            $rulesRef.Value = if ($null -ne $p) { $p.PolicyRules } else { $null }
            $null -ne $rulesRef.Value -and $rulesRef.Value -ne ''
        } 'must be a non-empty string' $failureRef

        Write-DcCheckResult 'Policy Rules XML file exists at registered path' {
            $null -ne $rulesRef.Value -and (Test-Path -LiteralPath $rulesRef.Value -PathType Leaf)
        } 'file at the registered path must exist' $failureRef

        Write-DcCheckResult 'Policy Rules XML parses as 3 PolicyRule records' {
            if ($null -eq $rulesRef.Value -or -not (Test-Path -LiteralPath $rulesRef.Value -PathType Leaf)) { return $false }
            @(Read-DcPolicyXml -Path $rulesRef.Value).Count -eq 3
        } 'must contain exactly 3 <PolicyRule> elements' $failureRef

        $expectedType = if ($ExpectMode -eq 'Audit') { 'AuditAllowed' } else { 'Deny' }
        Write-DcCheckResult "Rules XML uses Entry Type=$expectedType (matches ExpectMode)" {
            if ($null -eq $rulesRef.Value -or -not (Test-Path -LiteralPath $rulesRef.Value -PathType Leaf)) { return $false }
            $items = Read-DcPolicyXml -Path $rulesRef.Value
            foreach ($r in $items) {
                $types = @(([xml]$r.RawXml).PolicyRule.Entry.Type)
                if ($types -notcontains $expectedType) { return $false }
            }
            $true
        } "Mode $ExpectMode requires at least one $expectedType entry per rule" $failureRef

        Write-DcCheckResult 'Engine reports DeviceControlState != Disabled' {
            $prop = $status.PSObject.Properties['DeviceControlState']
            $null -ne $prop -and $prop.Value -ne 'Disabled' -and $prop.Value -ne 0
        } 'Get-MpComputerStatus.DeviceControlState must reflect engine consumed policy' $failureRef

        Write-DcCheckResult 'Engine reports DeviceControlPoliciesLastUpdated is recent (not 1601 sentinel)' {
            $prop = $status.PSObject.Properties['DeviceControlPoliciesLastUpdated']
            if ($null -eq $prop) { return $false }
            $v = $prop.Value
            if ($null -eq $v) { return $false }
            try { $dt = [datetime]$v } catch { return $false }
            $dt.Year -ge 2000
        } '1601-01-01 sentinel means engine never read the policy' $failureRef
    }

    Write-Host ""
    if ($failureRef.Value -eq 0) {
        Write-Host "Static checks: ALL PASSED" -ForegroundColor Green
    } else {
        Write-Host "Static checks: $($failureRef.Value) FAILED" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Dynamic verification (operator drives, USB stick required):" -ForegroundColor Yellow
    Write-Host "  1. Plug in a USB stick. It should mount and get a drive letter."
    Write-Host "  2. Open a file from the stick (Read should always work)."
    Write-Host "  3. Try to copy a file TO the stick."
    Write-Host "       Audit mode:   succeeds, Defender XDR Advanced Hunting records the event."
    Write-Host "       Enforce mode: fails with 'The media is write protected', toast shows."

    return ($failureRef.Value -eq 0)
}
