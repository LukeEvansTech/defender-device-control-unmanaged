function Get-DefenderDcPolicy {
<#
.SYNOPSIS
    Return the current Defender Device Control policy state as a structured object.

.DESCRIPTION
    Reads the canonical registry surface (under HKLM\SOFTWARE\Policies\Microsoft\
    Windows Defender\Device Control + Features\DeviceControlEnabled) and the
    Defender engine view via Get-MpComputerStatus; emits a [pscustomobject]
    suitable for piping or scripting. Use Test-DefenderDcPolicy for a PASS/FAIL
    summary instead.

.OUTPUTS
    PSCustomObject with properties:
      Mode                              - 'Audit' | 'Enforce' | 'Off' (derived from Entry Types in the Rules XML)
      FeaturesDeviceControlEnabled      - 0/1 or $null if absent
      DefaultEnforcement                - 0/1 or $null
      SecuredDevicesConfiguration       - string or $null
      PolicyGroupsXmlPath               - string or $null
      PolicyRulesXmlPath                - string or $null
      DeviceControlState                - 'Enabled' / 'Disabled' / etc. from engine
      DeviceControlPoliciesLastUpdated  - [datetime] or $null

.EXAMPLE
    Get-DefenderDcPolicy | Format-List

    Read the current policy state and format as a list.

.EXAMPLE
    $policy = Get-DefenderDcPolicy
    if ($policy.Mode -eq 'Enforce') { Write-Host 'Currently enforcing.' }

    Branch on the current mode.

.LINK
    https://lukeevanstech.github.io/defender-device-control-unmanaged/
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $feat = $null
    $defaultEnforcement = $null
    $securedClasses = $null
    $groupsXml = $null
    $rulesXml = $null

    $p = Get-ItemProperty -LiteralPath $script:DcFeatures -Name DeviceControlEnabled -ErrorAction SilentlyContinue
    if ($null -ne $p) { $feat = $p.DeviceControlEnabled }

    $p = Get-ItemProperty -LiteralPath $script:DcRoot -Name DefaultEnforcement -ErrorAction SilentlyContinue
    if ($null -ne $p) { $defaultEnforcement = $p.DefaultEnforcement }

    $p = Get-ItemProperty -LiteralPath $script:DcRoot -Name SecuredDevicesConfiguration -ErrorAction SilentlyContinue
    if ($null -ne $p) { $securedClasses = $p.SecuredDevicesConfiguration }

    $p = Get-ItemProperty -LiteralPath $script:DcGroupsKey -Name PolicyGroups -ErrorAction SilentlyContinue
    if ($null -ne $p) { $groupsXml = $p.PolicyGroups }

    $p = Get-ItemProperty -LiteralPath $script:DcRulesKey -Name PolicyRules -ErrorAction SilentlyContinue
    if ($null -ne $p) { $rulesXml = $p.PolicyRules }

    $mode = 'Off'
    if ($rulesXml -and (Test-Path -LiteralPath $rulesXml)) {
        try {
            $items = Read-DcPolicyXml -Path $rulesXml
            $allTypes = $items | ForEach-Object { ([xml]$_.RawXml).PolicyRule.Entry.Type }
            if ($allTypes -contains 'Deny') { $mode = 'Enforce' }
            elseif ($allTypes -contains 'AuditAllowed') { $mode = 'Audit' }
        } catch {
            Write-Warning "Get-DefenderDcPolicy: failed to read rules XML '$rulesXml' for mode detection: $($_.Exception.Message)"
        }
    }

    $deviceControlState = $null
    $deviceControlPoliciesLastUpdated = $null
    try {
        $status = Get-DcComputerStatus
        if ($null -ne $status) {
            $p1 = $status.PSObject.Properties['DeviceControlState']
            if ($null -ne $p1) { $deviceControlState = $p1.Value }
            $p2 = $status.PSObject.Properties['DeviceControlPoliciesLastUpdated']
            if ($null -ne $p2) { $deviceControlPoliciesLastUpdated = $p2.Value }
        }
    } catch {
        # On non-Windows or hosts without Defender, the engine view is unavailable.
        Write-Verbose "Get-DefenderDcPolicy: engine view unavailable: $($_.Exception.Message)"
    }

    [pscustomobject]@{
        Mode                             = $mode
        FeaturesDeviceControlEnabled     = $feat
        DefaultEnforcement               = $defaultEnforcement
        SecuredDevicesConfiguration      = $securedClasses
        PolicyGroupsXmlPath              = $groupsXml
        PolicyRulesXmlPath               = $rulesXml
        DeviceControlState               = $deviceControlState
        DeviceControlPoliciesLastUpdated = $deviceControlPoliciesLastUpdated
    }
}
