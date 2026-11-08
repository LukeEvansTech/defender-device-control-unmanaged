function ConvertTo-DcPolicyXml {
    <#
    .SYNOPSIS
        Build Defender Device Control policy XML (groups + audit/enforce rules)
        from a normalized restriction map.
    .DESCRIPTION
        Pure string generation, no I/O. Callers (New-DefenderDcPolicy) validate
        flag combinations before calling; this function assumes a sane map of
        class -> flag array. GUIDs are deterministic (New-DcDeterministicGuid),
        so identical input yields byte-identical XML.
    .PARAMETER Restrictions
        Hashtable: class name (Usb|Wpd|Optical) -> array of flags
        (ReadOnly|DenyExecute|Block|Allow).
    .PARAMETER AllowInstancePathId
        Instance path descriptors for the approved-devices exception group.
    .PARAMETER AllowHardwareId
        Hardware-ID descriptors for the approved-devices exception group.
    .PARAMETER PolicyName
        Label woven into group/rule names.
    .EXAMPLE
        ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly','DenyExecute') }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Restrictions,

        [string[]] $AllowInstancePathId = @(),

        [string[]] $AllowHardwareId = @(),

        [string] $PolicyName = 'Custom policy'
    )

    Set-StrictMode -Version Latest

    # Masks match the shipped starter XMLs: disk-style classes (USB removable,
    # optical) use 1/2/4; WPD uses 8/16/32.
    $classInfo = [ordered]@{
        Usb     = @{ PrimaryId = 'RemovableMediaDevices'; Read = 1; Write = 2;  Execute = 4;  Label = 'removable storage' }
        Wpd     = @{ PrimaryId = 'WpdDevices';            Read = 8; Write = 16; Execute = 32; Label = 'WPD / MTP devices' }
        Optical = @{ PrimaryId = 'CdRomDevices';          Read = 1; Write = 2;  Execute = 4;  Label = 'optical drives' }
    }

    foreach ($key in $Restrictions.Keys) {
        if (-not $classInfo.Contains($key)) {
            throw "ConvertTo-DcPolicyXml: unknown device class '$key'. Valid: $($classInfo.Keys -join ', ')."
        }
    }

    $escape = [System.Security.SecurityElement]
    $hasExceptions = (@($AllowInstancePathId).Count + @($AllowHardwareId).Count) -gt 0
    $approvedGroupId = New-DcDeterministicGuid -Seed 'ddcu:group:approved'
    $safeName = $escape::Escape($PolicyName)

    # Per-class derived state, in fixed classInfo order for deterministic output.
    $classes = foreach ($class in @($classInfo.Keys)) {
        if (-not $Restrictions.ContainsKey($class)) { continue }
        $info  = $classInfo[$class]
        $flags = @($Restrictions[$class])
        $fullMask = $info.Read + $info.Write + $info.Execute
        $denyMask = 0
        if ($flags -contains 'Block') {
            $denyMask = $fullMask
        } else {
            if ($flags -contains 'ReadOnly')    { $denyMask += $info.Write }
            if ($flags -contains 'DenyExecute') { $denyMask += $info.Execute }
        }
        $isAllow = $flags -contains 'Allow'
        if ($flags -contains 'Block')       { $summary = 'block all access' }
        elseif ($isAllow)                   { $summary = 'allow (audit only)' }
        else {
            $parts = @()
            if ($flags -contains 'ReadOnly')    { $parts += 'write' }
            if ($flags -contains 'DenyExecute') { $parts += 'execute' }
            $summary = 'deny ' + ($parts -join '+')
        }
        $lower = $class.ToLowerInvariant()
        [pscustomobject]@{
            Class     = $class
            Info      = $info
            DenyMask  = $denyMask
            AuditMask = if ($isAllow) { $fullMask } else { $denyMask }
            IsAllow   = $isAllow
            Summary   = $summary
            GroupId   = New-DcDeterministicGuid -Seed "ddcu:group:$lower"
            RuleId    = New-DcDeterministicGuid -Seed "ddcu:rule:$lower"
            AuditEntryId       = New-DcDeterministicGuid -Seed "ddcu:entry:${lower}:auditallowed"
            DenyEntryId        = New-DcDeterministicGuid -Seed "ddcu:entry:${lower}:deny"
            AuditDeniedEntryId = New-DcDeterministicGuid -Seed "ddcu:entry:${lower}:auditdenied"
        }
    }

    # --- PolicyGroups.xml ---
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<Groups>')
    foreach ($c in $classes) {
        [void]$sb.AppendLine("  <Group Id=`"$($c.GroupId)`" Type=`"Device`">")
        [void]$sb.AppendLine("    <Name>$safeName - $($escape::Escape($c.Info.Label))</Name>")
        [void]$sb.AppendLine('    <MatchType>MatchAny</MatchType>')
        [void]$sb.AppendLine('    <DescriptorIdList>')
        [void]$sb.AppendLine("      <PrimaryId>$($c.Info.PrimaryId)</PrimaryId>")
        [void]$sb.AppendLine('    </DescriptorIdList>')
        [void]$sb.AppendLine('  </Group>')
    }
    if ($hasExceptions) {
        [void]$sb.AppendLine("  <Group Id=`"$approvedGroupId`" Type=`"Device`">")
        [void]$sb.AppendLine('    <Name>Approved devices</Name>')
        [void]$sb.AppendLine('    <MatchType>MatchAny</MatchType>')
        [void]$sb.AppendLine('    <DescriptorIdList>')
        foreach ($id in $AllowInstancePathId) {
            [void]$sb.AppendLine("      <InstancePathId>$($escape::Escape($id))</InstancePathId>")
        }
        foreach ($id in $AllowHardwareId) {
            [void]$sb.AppendLine("      <HardwareId>$($escape::Escape($id))</HardwareId>")
        }
        [void]$sb.AppendLine('    </DescriptorIdList>')
        [void]$sb.AppendLine('  </Group>')
    }
    [void]$sb.AppendLine('</Groups>')
    $groupsXml = $sb.ToString()

    # Shared rule-opening emitter: IncludedIdList + ExcludedIdList wiring.
    $openRule = {
        param([System.Text.StringBuilder] $b, $c, [string] $name, [bool] $excludeApproved)
        [void]$b.AppendLine("  <PolicyRule Id=`"$($c.RuleId)`">")
        [void]$b.AppendLine("    <Name>$name</Name>")
        [void]$b.AppendLine('    <IncludedIdList>')
        [void]$b.AppendLine("      <GroupId>$($c.GroupId)</GroupId>")
        [void]$b.AppendLine('    </IncludedIdList>')
        if ($excludeApproved) {
            [void]$b.AppendLine('    <ExcludedIdList>')
            [void]$b.AppendLine("      <GroupId>$approvedGroupId</GroupId>")
            [void]$b.AppendLine('    </ExcludedIdList>')
        } else {
            [void]$b.AppendLine('    <ExcludedIdList></ExcludedIdList>')
        }
    }
    $emitEntry = {
        param([System.Text.StringBuilder] $b, [string] $entryId, [string] $type, [int] $options, [int] $mask)
        [void]$b.AppendLine("    <Entry Id=`"$entryId`">")
        [void]$b.AppendLine("      <Type>$type</Type>")
        [void]$b.AppendLine("      <Options>$options</Options>")
        [void]$b.AppendLine("      <AccessMask>$mask</AccessMask>")
        [void]$b.AppendLine('    </Entry>')
    }

    # --- PolicyRules.Audit.xml ---
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<PolicyRules>')
    foreach ($c in $classes) {
        $name = "$safeName - audit on $($escape::Escape($c.Info.Label))"
        $exclude = $hasExceptions -and -not $c.IsAllow
        & $openRule $sb $c $name $exclude
        & $emitEntry $sb $c.AuditEntryId 'AuditAllowed' 2 $c.AuditMask
        [void]$sb.AppendLine('  </PolicyRule>')
    }
    [void]$sb.AppendLine('</PolicyRules>')
    $auditXml = $sb.ToString()

    # --- PolicyRules.Enforce.xml --- (Allow classes contribute nothing here)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<PolicyRules>')
    foreach ($c in $classes) {
        if ($c.DenyMask -eq 0) { continue }
        $name = "$safeName - $($escape::Escape($c.Summary)) on $($escape::Escape($c.Info.Label))"
        & $openRule $sb $c $name $hasExceptions
        & $emitEntry $sb $c.DenyEntryId 'Deny' 0 $c.DenyMask
        & $emitEntry $sb $c.AuditDeniedEntryId 'AuditDenied' 3 $c.DenyMask
        [void]$sb.AppendLine('  </PolicyRule>')
    }
    [void]$sb.AppendLine('</PolicyRules>')
    $enforceXml = $sb.ToString()

    # AppendLine emits Environment.NewLine (CRLF on Windows); the byte-identical
    # contract requires one canonical form on every OS. Starters use LF.
    $groupsXml  = $groupsXml  -replace "`r`n", "`n"
    $auditXml   = $auditXml   -replace "`r`n", "`n"
    $enforceXml = $enforceXml -replace "`r`n", "`n"

    [pscustomobject]@{
        GroupsXml       = $groupsXml
        AuditRulesXml   = $auditXml
        EnforceRulesXml = $enforceXml
    }
}
