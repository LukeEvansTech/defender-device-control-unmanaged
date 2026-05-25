function Set-DefenderDcPolicy {
<#
.SYNOPSIS
    Apply or remove the Defender Device Control read-only USB policy on an
    unmanaged Windows 11 device, using the canonical Local GPO registry
    surface (file-path REG_SZ + XML, per WindowsDefender.admx).

.DESCRIPTION
    Writes 5 registry values under HKLM\SOFTWARE\Policies\Microsoft\Windows
    Defender\... that point Defender at policy XMLs describing the device
    groups and per-class deny rules. By default, ships starter XMLs covering
    removable storage, WPD/MTP, and optical drives. Supply -GroupsXmlPath
    and -RulesXmlPath to deploy your own.

    Requires administrator elevation. Requires MDE attach for the engine to
    consume policy (registry writes succeed on any box; engine activation
    requires Microsoft Defender for Endpoint).

.PARAMETER Mode
    Audit (log without block), Enforce (block + log), or Off (remove policy).

.PARAMETER GroupsXmlPath
    Optional absolute path to a PolicyGroups.xml. Defaults to the shipped
    starter XML.

.PARAMETER RulesXmlPath
    Optional absolute path to a PolicyRules.<Mode>.xml. Defaults to the
    shipped starter XML matching the selected -Mode.

.PARAMETER SkipMpCmdRunValidation
    Skip the engine-side XML preflight via MpCmdRun.exe -DeviceControl
    -TestPolicyXml. Off by default - validation recommended.

.PARAMETER SkipGpUpdate
    Skip the trailing gpupdate /force. gpupdate is the canonical trigger
    that makes Defender consume the policy. Skipping leaves the registry
    written but the engine may not pick up the policy until the next
    OS-driven refresh.

.EXAMPLE
    Set-DefenderDcPolicy -Mode Audit -WhatIf

    Preview the planned registry writes without applying.

.EXAMPLE
    Set-DefenderDcPolicy -Mode Enforce

    Apply policy in Enforce mode.

.EXAMPLE
    Set-DefenderDcPolicy -Mode Enforce -GroupsXmlPath 'C:\MyPolicy\Groups.xml' -RulesXmlPath 'C:\MyPolicy\Rules.xml'

    Deploy a custom policy XML pair.

.EXAMPLE
    Set-DefenderDcPolicy -Mode Off

    Remove the policy entirely.

.LINK
    https://lukeevanstech.github.io/defender-device-control-unmanaged/
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Audit','Enforce','Off')]
        [string] $Mode,

        [string] $GroupsXmlPath,

        [string] $RulesXmlPath,

        [switch] $SkipMpCmdRunValidation,

        [switch] $SkipGpUpdate
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-DcIsElevated)) { throw "Set-DefenderDcPolicy: must be run elevated." }

    $transcript = Start-DcTranscript -CmdletName 'Set-DefenderDcPolicy'
    try {
        try { $defender = Get-DcComputerStatus } catch {
            # Wrap the original ErrorRecord so the caller still has the typed exception + stack trace.
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    "Set-DefenderDcPolicy: Get-MpComputerStatus failed: $($_.Exception.Message)",
                    $_.Exception),
                'DefenderDeviceControlUnmanaged.DefenderQueryFailed',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $null)
        }
        if (-not $defender.AMServiceEnabled) { throw "Set-DefenderDcPolicy: Defender service not enabled." }
        Write-Verbose "Defender AM engine $($defender.AMEngineVersion), TamperProtection=$($defender.IsTamperProtected)"

        if ($Mode -eq 'Off') {
            Write-Verbose "Removing Device Control policy."
            if ($PSCmdlet.ShouldProcess('Device Control policy registry', 'Remove policy state')) {
                Remove-DcPolicy
                if (-not $SkipGpUpdate -and $PSCmdlet.ShouldProcess('Group Policy', 'gpupdate /force')) {
                    & gpupdate.exe /force 2>&1 | ForEach-Object { Write-Verbose "  $_" }
                }
                if ($PSCmdlet.ShouldProcess('Defender engine', 'Update-MpSignature')) {
                    Update-MpSignature -UpdateSource MMPC -ErrorAction SilentlyContinue
                }
            }
            return
        }

        $defaultPolicyDir = Join-Path $PSScriptRoot '..\policy'
        if (-not $GroupsXmlPath) { $GroupsXmlPath = Join-Path $defaultPolicyDir 'PolicyGroups.xml' }
        if (-not $RulesXmlPath)  { $RulesXmlPath  = Join-Path $defaultPolicyDir "PolicyRules.$Mode.xml" }
        $GroupsXmlPath = [System.IO.Path]::GetFullPath($GroupsXmlPath)
        $RulesXmlPath  = [System.IO.Path]::GetFullPath($RulesXmlPath)

        foreach ($p in $GroupsXmlPath, $RulesXmlPath) {
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
                throw "Set-DefenderDcPolicy: required policy file not found: $p"
            }
        }

        Write-Verbose "Groups: $GroupsXmlPath"
        Write-Verbose "Rules:  $RulesXmlPath"

        # Use the public Test-DefenderDcPolicyXml validator (which layers BOM /
        # xml-declaration / PolicyRule.Name-as-child / Options-bitmask checks on
        # top of Read-DcPolicyXml + MpCmdRun) so a caller-supplied XML faces the
        # same contract whether they ran Test-DefenderDcPolicyXml first or not.
        if (-not (Test-DefenderDcPolicyXml -Path $GroupsXmlPath -Kind Groups -SkipEngineValidation:$SkipMpCmdRunValidation)) {
            throw "Set-DefenderDcPolicy: GroupsXmlPath failed validation: $GroupsXmlPath"
        }
        if (-not (Test-DefenderDcPolicyXml -Path $RulesXmlPath -Kind Rules -SkipEngineValidation:$SkipMpCmdRunValidation)) {
            throw "Set-DefenderDcPolicy: RulesXmlPath failed validation: $RulesXmlPath"
        }

        $manifest = Get-DcRegistryManifest -GroupsXmlPath $GroupsXmlPath -RulesXmlPath $RulesXmlPath

        if ($PSCmdlet.ShouldProcess('Device Control policy registry', "Apply $Mode policy state")) {
            Write-Verbose "Removing any prior Device Control policy state before re-applying."
            Remove-DcPolicy

            Invoke-DcRegistryWrites -Manifest $manifest

            if (-not $SkipGpUpdate -and $PSCmdlet.ShouldProcess('Group Policy', 'gpupdate /force')) {
                & gpupdate.exe /force 2>&1 | ForEach-Object { Write-Verbose "  $_" }
            }

            if ($PSCmdlet.ShouldProcess('Defender engine', 'Update-MpSignature')) {
                Update-MpSignature -UpdateSource MMPC -ErrorAction SilentlyContinue
            }
        }
    }
    finally {
        # Stop-Transcript throws "host is not currently transcribing" under -WhatIf
        # (Start-Transcript honors $WhatIfPreference and becomes a no-op). The
        # finally block must clean up regardless; swallow the benign case.
        try { Stop-Transcript | Out-Null } catch { }
        Write-Verbose "Set-DefenderDcPolicy transcript: $transcript"
    }
}
