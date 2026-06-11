function New-DefenderDcPolicy {
    <#
    .SYNOPSIS
        Craft a custom Defender Device Control policy XML set from simple
        per-class restriction parameters.

    .DESCRIPTION
        Generates the same three-file policy shape this module ships
        (PolicyGroups.xml, PolicyRules.Audit.xml, PolicyRules.Enforce.xml) so
        the audit-first-then-enforce workflow stays a one-flag switch at apply
        time. Pure generation: no registry access, no elevation, runs on any
        platform. Apply the result with Set-DefenderDcPolicy (pipeline or
        -GroupsXmlPath/-RulesXmlPath).

        Group/rule/entry GUIDs are deterministic (hash-derived from stable
        seeds), so regenerating the same policy yields byte-identical XML.

    .PARAMETER Usb
        Restriction flags for removable storage (RemovableMediaDevices):
        ReadOnly, DenyExecute, Block, Allow. ReadOnly+DenyExecute may combine;
        Block and Allow are exclusive.

    .PARAMETER Wpd
        Restriction flags for WPD/MTP devices (phones, cameras). Same
        vocabulary as -Usb.

    .PARAMETER Optical
        Restriction flags for CD/DVD drives. Same vocabulary as -Usb.

    .PARAMETER AllowHardwareId
        Hardware-ID strings exempted from all restrictions (model-wide match).

    .PARAMETER AllowDevice
        Device objects from Get-DefenderDcDevice (pipeline-friendly). Each
        contributes its InstancePathId (serial-specific match).

    .PARAMETER AllowDeviceFile
        Path to a JSON device list written by Get-DefenderDcDevice -OutFile.

    .PARAMETER OutputPath
        Directory for the generated XML files. Created if missing. Defaults
        to the current directory.

    .PARAMETER PolicyName
        Label woven into group/rule names. Defaults to 'Custom policy'.

    .EXAMPLE
        New-DefenderDcPolicy -Usb ReadOnly,DenyExecute -Wpd ReadOnly -OutputPath .\policy\

        USB read-only with no execute, WPD read-only; XML pair written to .\policy\.

    .EXAMPLE
        Get-DefenderDcDevice -Watch -OutFile .\approved.json
        New-DefenderDcPolicy -Usb ReadOnly -AllowDeviceFile .\approved.json -OutputPath .\policy\ |
            Set-DefenderDcPolicy -Mode Audit

        Capture approved sticks, craft a policy exempting them, apply in Audit mode.

    .EXAMPLE
        New-DefenderDcPolicy -Usb Block -Optical Block -AllowHardwareId 'USBSTOR\DiskKingstonDataTraveler_3.0'

        Block USB and optical entirely except Kingston DataTraveler 3.0 models.

    .LINK
        https://lukeevanstech.github.io/defender-device-control-unmanaged/
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('ReadOnly','DenyExecute','Block','Allow')]
        [string[]] $Usb,

        [ValidateSet('ReadOnly','DenyExecute','Block','Allow')]
        [string[]] $Wpd,

        [ValidateSet('ReadOnly','DenyExecute','Block','Allow')]
        [string[]] $Optical,

        [string[]] $AllowHardwareId = @(),

        [Parameter(ValueFromPipeline)]
        [pscustomobject[]] $AllowDevice,

        [string] $AllowDeviceFile,

        [string] $OutputPath = '.',

        [string] $PolicyName = 'Custom policy'
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $restrictions = @{}
        foreach ($pair in @(
                @{ Name = 'Usb'; Value = $Usb },
                @{ Name = 'Wpd'; Value = $Wpd },
                @{ Name = 'Optical'; Value = $Optical })) {
            if ($null -eq $pair.Value) { continue }
            $flags = @($pair.Value | Select-Object -Unique)
            foreach ($exclusive in 'Block','Allow') {
                if ($flags -contains $exclusive -and $flags.Count -gt 1) {
                    throw "New-DefenderDcPolicy: -$($pair.Name): '$exclusive' cannot be combined with other flags."
                }
            }
            $restrictions[$pair.Name] = $flags
        }
        if ($restrictions.Count -eq 0) {
            throw 'New-DefenderDcPolicy: specify at least one of -Usb, -Wpd, -Optical.'
        }

        $pipelineDevices = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($d in @($AllowDevice)) {
            if ($null -ne $d) { $pipelineDevices.Add($d) }
        }
    }

    end {
        # Gather exception descriptors from the file and the pipeline; both
        # contribute InstancePathId (serial-specific). -AllowHardwareId strings
        # pass through as model-wide HardwareId descriptors.
        $fileDevices = @()
        if ($AllowDeviceFile) {
            if (-not (Test-Path -LiteralPath $AllowDeviceFile -PathType Leaf)) {
                throw "New-DefenderDcPolicy: -AllowDeviceFile not found: $AllowDeviceFile"
            }
            $raw = Get-Content -LiteralPath $AllowDeviceFile -Raw
            try { $fileDevices = @($raw | ConvertFrom-Json) } catch {
                throw "New-DefenderDcPolicy: -AllowDeviceFile is not valid JSON: $AllowDeviceFile ($($_.Exception.Message))"
            }
        }

        $instanceIds = [System.Collections.Generic.List[string]]::new()
        foreach ($d in (@($fileDevices) + @($pipelineDevices))) {
            $prop = $d.PSObject.Properties['InstancePathId']
            if ($null -eq $prop -or [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                throw "New-DefenderDcPolicy: device record has no InstancePathId (expected output of Get-DefenderDcDevice): $($d | ConvertTo-Json -Compress -Depth 3)"
            }
            if (-not ($instanceIds -contains [string]$prop.Value)) {
                $instanceIds.Add([string]$prop.Value)
            }
        }
        $hardwareIds = @($AllowHardwareId | Where-Object { $_ } | Select-Object -Unique)

        $xml = ConvertTo-DcPolicyXml -Restrictions $restrictions `
            -AllowInstancePathId $instanceIds.ToArray() `
            -AllowHardwareId $hardwareIds `
            -PolicyName $PolicyName

        $resolvedOut = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)
        $groupsPath  = Join-Path $resolvedOut 'PolicyGroups.xml'
        $auditPath   = Join-Path $resolvedOut 'PolicyRules.Audit.xml'
        $enforcePath = Join-Path $resolvedOut 'PolicyRules.Enforce.xml'

        if ($PSCmdlet.ShouldProcess($resolvedOut, 'Write Device Control policy XML files')) {
            if (-not (Test-Path -LiteralPath $resolvedOut -PathType Container)) {
                New-Item -Path $resolvedOut -ItemType Directory -Force | Out-Null
            }

            # All three strings are built before any write, so a failure cannot
            # leave a partially-generated policy on disk. WriteAllText emits
            # UTF-8 without BOM (the engine validator rejects BOMs).
            [System.IO.File]::WriteAllText($groupsPath,  $xml.GroupsXml)
            [System.IO.File]::WriteAllText($auditPath,   $xml.AuditRulesXml)
            [System.IO.File]::WriteAllText($enforcePath, $xml.EnforceRulesXml)

            Write-Verbose "Wrote $groupsPath"
            Write-Verbose "Wrote $auditPath"
            Write-Verbose "Wrote $enforcePath"
        }

        $allAllow = ($restrictions.Values | ForEach-Object { $_ -contains 'Allow' }) -notcontains $false
        if ($allAllow) {
            Write-Warning 'New-DefenderDcPolicy: all classes are Allow - the Enforce rules file contains no rules and cannot be applied with -Mode Enforce. Use -Mode Audit.'
        }

        [pscustomobject]@{
            PSTypeName          = 'DefenderDeviceControlUnmanaged.PolicyFiles'
            GroupsXmlPath       = $groupsPath
            AuditRulesXmlPath   = $auditPath
            EnforceRulesXmlPath = $enforcePath
        }
    }
}
