# Policy Builder + Device Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `New-DefenderDcPolicy` (parameter-driven policy XML builder) and `Get-DefenderDcDevice` (hardware-ID capture, snapshot + live watch) to the DefenderDeviceControlUnmanaged module, plus pipeline support on `Set-DefenderDcPolicy`.

**Architecture:** Pure-generation builder (no registry/elevation) writes the same three-file XML shape the module ships (`PolicyGroups.xml`, `PolicyRules.Audit.xml`, `PolicyRules.Enforce.xml`) with deterministic (seed-hashed) GUIDs. Capture cmdlet wraps CIM `Win32_PnPEntity` queries/events behind small mockable private helpers. Spec: `docs/superpowers/specs/2026-06-11-policy-builder-and-device-capture-design.md`.

**Tech Stack:** PowerShell (5.1 + 7.x compatible), Pester 5, CIM cmdlets. House style: one function per file, `Dc` prefix for Private helpers, `DefenderDc` for Public, comment-based help mandatory (a unit test enforces SYNOPSIS + EXAMPLE on every exported function), `Set-StrictMode -Version Latest` inside function bodies, errors thrown as `"FunctionName: message"`.

**Key paths:**

- Module source: `src/DefenderDeviceControlUnmanaged/` (`Public/`, `Private/`, `policy/`, `examples/`)
- Tests: `src/Tests/Unit/<FunctionName>.Tests.ps1`
- The dev psm1 auto-dot-sources `Public/*.ps1` + `Private/*.ps1` and exports public basenames — adding files needs **no psm1 change**, but `psd1 FunctionsToExport` and `ExportedFunctions.Tests.ps1` must be updated (Task 9).

**Run tests with:**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/<File>.Tests.ps1 -Output Detailed"
```

(On this macOS dev box `pwsh` is available; CI also runs Windows PowerShell 5.1 — avoid PS7-only syntax: no `??`, no `?.`, no `-AsArray` on ConvertTo-Json, no ternary.)

**AccessMask reference (from the shipped starter XMLs — do not invent other values):**

| Class   | PrimaryId             | Read | Write | Execute |
| ------- | --------------------- | ---- | ----- | ------- |
| Usb     | RemovableMediaDevices | 1    | 2     | 4       |
| Optical | CdRomDevices          | 1    | 2     | 4       |
| Wpd     | WpdDevices            | 8    | 16    | 32      |

Entry patterns (match starter XMLs exactly): Audit file → `AuditAllowed` with `<Options>2`; Enforce file → `Deny` with `<Options>0` **plus** `AuditDenied` with `<Options>3`. `<Type>` is a child element of `<Entry>`, never an attribute. No `<?xml?>` declaration, no BOM (the module's own `Test-DefenderDcPolicyXml` rejects both).

---

## Task 1: Private helper `New-DcDeterministicGuid`

Deterministic UUIDv5-style GUIDs so regenerating a policy yields byte-identical XML (clean diffs, exact tests).

**Files:**

- Create: `src/DefenderDeviceControlUnmanaged/Private/New-DcDeterministicGuid.ps1`
- Test: `src/Tests/Unit/New-DcDeterministicGuid.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\New-DcDeterministicGuid.ps1')
}

Describe 'New-DcDeterministicGuid' {
    It 'returns a braced GUID string' {
        New-DcDeterministicGuid -Seed 'ddcu:rule:usb' |
            Should -Match '^\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$'
    }

    It 'is deterministic: same seed, same GUID' {
        $a = New-DcDeterministicGuid -Seed 'ddcu:group:approved'
        $b = New-DcDeterministicGuid -Seed 'ddcu:group:approved'
        $a | Should -Be $b
    }

    It 'different seeds produce different GUIDs' {
        (New-DcDeterministicGuid -Seed 'ddcu:rule:usb') |
            Should -Not -Be (New-DcDeterministicGuid -Seed 'ddcu:rule:wpd')
    }

    It 'does not collide with the shipped starter XML GUIDs' {
        $starter = @(
            '{18c18655-7803-4235-a811-3da676a1f197}',
            '{b9854cf9-b7e3-4155-b0ec-5031d44657b3}',
            '{c145b8d2-2799-469b-8014-927e7dd9babf}',
            '{77d21842-eba0-44a7-a46a-1c0291b087e0}',
            '{d1a03385-6742-4f39-b05f-7f7f5c5bee1e}',
            '{f3c3878f-3133-4b5a-83e8-4b4b79c35591}'
        )
        foreach ($seed in 'ddcu:group:usb','ddcu:group:wpd','ddcu:group:optical','ddcu:group:approved','ddcu:rule:usb','ddcu:rule:wpd','ddcu:rule:optical') {
            $starter | Should -Not -Contain (New-DcDeterministicGuid -Seed $seed)
        }
    }

    It 'throws on an empty seed' {
        { New-DcDeterministicGuid -Seed '' } | Should -Throw
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/New-DcDeterministicGuid.Tests.ps1 -Output Detailed"`
Expected: FAIL — `New-DcDeterministicGuid` is not recognized (dot-source of missing file errors in BeforeAll).

- [ ] **Step 3: Write the implementation**

```powershell
function New-DcDeterministicGuid {
    <#
    .SYNOPSIS
        Derive a stable GUID from a seed string (UUIDv5-style).
    .DESCRIPTION
        SHA-1 of a fixed module namespace prefix + the seed, with the UUID
        version/variant bits set. The contract is determinism (same seed ->
        same GUID, forever), so generated policy XML is byte-identical across
        runs. RFC 4122 byte ordering is not required for that and is not
        attempted.
    .PARAMETER Seed
        Stable seed string, e.g. 'ddcu:rule:usb'.
    .EXAMPLE
        New-DcDeterministicGuid -Seed 'ddcu:group:approved'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Seed
    )

    Set-StrictMode -Version Latest

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("DefenderDeviceControlUnmanaged:$Seed"))
    } finally {
        $sha1.Dispose()
    }

    $bytes = $hash[0..15]
    $bytes[6] = [byte](($bytes[6] -band 0x0F) -bor 0x50)   # version 5
    $bytes[8] = [byte](($bytes[8] -band 0x3F) -bor 0x80)   # RFC 4122 variant

    '{' + ([guid]::new([byte[]]$bytes)).ToString() + '}'
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/New-DcDeterministicGuid.Tests.ps1 -Output Detailed"`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/Private/New-DcDeterministicGuid.ps1 src/Tests/Unit/New-DcDeterministicGuid.Tests.ps1
git commit -m "feat: add New-DcDeterministicGuid private helper"
```

---

## Task 2: Private helper `ConvertTo-DcPolicyXml`

The XML generation core: normalized restrictions in, three XML strings out. All policy-semantics knowledge (masks, entry patterns, exclusion wiring) lives here.

**Files:**

- Create: `src/DefenderDeviceControlUnmanaged/Private/ConvertTo-DcPolicyXml.ps1`
- Test: `src/Tests/Unit/ConvertTo-DcPolicyXml.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\New-DcDeterministicGuid.ps1')
    . (Join-Path $ModuleRoot 'Private\ConvertTo-DcPolicyXml.ps1')
}

Describe 'ConvertTo-DcPolicyXml' {
    It 'is deterministic: identical input yields identical output' {
        $splat = @{ Restrictions = @{ Usb = @('ReadOnly','DenyExecute') }; AllowHardwareId = @('USBSTOR\DiskKingston') }
        $a = ConvertTo-DcPolicyXml @splat
        $b = ConvertTo-DcPolicyXml @splat
        $a.GroupsXml      | Should -Be $b.GroupsXml
        $a.AuditRulesXml  | Should -Be $b.AuditRulesXml
        $a.EnforceRulesXml | Should -Be $b.EnforceRulesXml
    }

    It 'emits no xml declaration and no BOM-prone leading whitespace' {
        $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly') }
        $r.GroupsXml | Should -Not -Match '^\s*<\?xml'
        $r.GroupsXml | Should -Match '^<Groups>'
    }

    Context 'masks' {
        It 'Usb ReadOnly,DenyExecute denies write+execute (mask 6)' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly','DenyExecute') }
            ([xml]$r.EnforceRulesXml).PolicyRules.PolicyRule.Entry |
                Where-Object { $_.Type -eq 'Deny' } |
                ForEach-Object { $_.AccessMask } | Should -Be '6'
        }

        It 'Wpd ReadOnly denies write only with WPD mask (16)' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Wpd = @('ReadOnly') }
            ([xml]$r.EnforceRulesXml).PolicyRules.PolicyRule.Entry |
                Where-Object { $_.Type -eq 'Deny' } |
                ForEach-Object { $_.AccessMask } | Should -Be '16'
        }

        It 'Optical Block denies read+write+execute (mask 7)' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Optical = @('Block') }
            ([xml]$r.EnforceRulesXml).PolicyRules.PolicyRule.Entry |
                Where-Object { $_.Type -eq 'Deny' } |
                ForEach-Object { $_.AccessMask } | Should -Be '7'
        }
    }

    Context 'rule shape' {
        It 'enforce rules carry a Deny (Options 0) and an AuditDenied (Options 3) entry' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly') }
            $entries = @(([xml]$r.EnforceRulesXml).PolicyRules.PolicyRule.Entry)
            ($entries | Where-Object { $_.Type -eq 'Deny' }).Options | Should -Be '0'
            ($entries | Where-Object { $_.Type -eq 'AuditDenied' }).Options | Should -Be '3'
        }

        It 'audit rules carry a single AuditAllowed (Options 2) entry with the deny mask' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly') }
            $entries = @(([xml]$r.AuditRulesXml).PolicyRules.PolicyRule.Entry)
            $entries.Count | Should -Be 1
            $entries[0].Type | Should -Be 'AuditAllowed'
            $entries[0].Options | Should -Be '2'
            $entries[0].AccessMask | Should -Be '2'
        }

        It 'rule Ids match between audit and enforce files' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly'); Wpd = @('Block') }
            $auditIds   = @(([xml]$r.AuditRulesXml).PolicyRules.PolicyRule)   | ForEach-Object { $_.Id } | Sort-Object
            $enforceIds = @(([xml]$r.EnforceRulesXml).PolicyRules.PolicyRule) | ForEach-Object { $_.Id } | Sort-Object
            $enforceIds | Should -Be $auditIds
        }
    }

    Context 'Allow semantics' {
        It 'Allow class gets an audit rule with the full mask and no enforce rule' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly'); Wpd = @('Allow') }
            @(([xml]$r.AuditRulesXml).PolicyRules.PolicyRule).Count | Should -Be 2
            @(([xml]$r.EnforceRulesXml).PolicyRules.PolicyRule).Count | Should -Be 1
            $wpdAudit = @(([xml]$r.AuditRulesXml).PolicyRules.PolicyRule) |
                Where-Object { $_.Name -like '*WPD*' }
            $wpdAudit.Entry.AccessMask | Should -Be '56'
        }
    }

    Context 'exceptions' {
        It 'no exceptions: no approved group, empty ExcludedIdList' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly') }
            @(([xml]$r.GroupsXml).Groups.Group).Count | Should -Be 1
            $r.EnforceRulesXml | Should -Match '<ExcludedIdList></ExcludedIdList>'
            $r.EnforceRulesXml | Should -Not -Match '<ExcludedIdList>\s*<GroupId>'
        }

        It 'exceptions create one approved group referenced from every deny rule ExcludedIdList' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly'); Optical = @('Block') } `
                -AllowInstancePathId @('USBSTOR\DISK&VEN_K\SER1&0') -AllowHardwareId @('USBSTOR\DiskKingston')
            $groups = @(([xml]$r.GroupsXml).Groups.Group)
            $groups.Count | Should -Be 3
            $approved = $groups | Where-Object { $_.Name -eq 'Approved devices' }
            @($approved.DescriptorIdList.InstancePathId).Count | Should -Be 1
            @($approved.DescriptorIdList.HardwareId).Count | Should -Be 1
            foreach ($rule in @(([xml]$r.EnforceRulesXml).PolicyRules.PolicyRule)) {
                $rule.ExcludedIdList.GroupId | Should -Be $approved.Id
            }
        }

        It 'XML-escapes descriptor values' {
            $r = ConvertTo-DcPolicyXml -Restrictions @{ Usb = @('ReadOnly') } -AllowHardwareId @('AB&CD<>')
            { [xml]$r.GroupsXml } | Should -Not -Throw
            $r.GroupsXml | Should -Match 'AB&amp;CD&lt;&gt;'
        }
    }

    It 'throws on an unknown class key' {
        { ConvertTo-DcPolicyXml -Restrictions @{ Floppy = @('Block') } } | Should -Throw -ExpectedMessage '*unknown device class*'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/ConvertTo-DcPolicyXml.Tests.ps1 -Output Detailed"`
Expected: FAIL — `ConvertTo-DcPolicyXml` file missing.

- [ ] **Step 3: Write the implementation**

```powershell
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

    [pscustomobject]@{
        GroupsXml       = $groupsXml
        AuditRulesXml   = $auditXml
        EnforceRulesXml = $enforceXml
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/ConvertTo-DcPolicyXml.Tests.ps1 -Output Detailed"`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/Private/ConvertTo-DcPolicyXml.ps1 src/Tests/Unit/ConvertTo-DcPolicyXml.Tests.ps1
git commit -m "feat: add ConvertTo-DcPolicyXml policy generation core"
```

---

## Task 3: Public cmdlet `New-DefenderDcPolicy`

Parameter surface, flag-combo validation, exception merging (inline + file + pipeline), file writing, result object.

**Files:**

- Create: `src/DefenderDeviceControlUnmanaged/Public/New-DefenderDcPolicy.ps1`
- Test: `src/Tests/Unit/New-DefenderDcPolicy.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\New-DcDeterministicGuid.ps1')
    . (Join-Path $ModuleRoot 'Private\ConvertTo-DcPolicyXml.ps1')
    . (Join-Path $ModuleRoot 'Private\Read-DcPolicyXml.ps1')
    . (Join-Path $ModuleRoot 'Public\New-DefenderDcPolicy.ps1')
}

Describe 'New-DefenderDcPolicy' {
    Context 'parameter validation' {
        It 'throws when no class parameter is supplied' {
            { New-DefenderDcPolicy -OutputPath $TestDrive } |
                Should -Throw -ExpectedMessage '*at least one of -Usb, -Wpd, -Optical*'
        }

        It 'rejects Block combined with other flags' {
            { New-DefenderDcPolicy -Usb Block,ReadOnly -OutputPath $TestDrive } |
                Should -Throw -ExpectedMessage '*cannot be combined*'
        }

        It 'rejects Allow combined with other flags' {
            { New-DefenderDcPolicy -Wpd Allow,DenyExecute -OutputPath $TestDrive } |
                Should -Throw -ExpectedMessage '*cannot be combined*'
        }

        It 'rejects flag values outside the set' {
            { New-DefenderDcPolicy -Usb Bogus -OutputPath $TestDrive } | Should -Throw
        }

        It 'throws on a missing -AllowDeviceFile' {
            { New-DefenderDcPolicy -Usb ReadOnly -AllowDeviceFile (Join-Path $TestDrive 'nope.json') -OutputPath $TestDrive } |
                Should -Throw -ExpectedMessage '*not found*'
        }

        It 'throws when a device file record lacks InstancePathId' {
            $bad = Join-Path $TestDrive 'bad.json'
            '[{"FriendlyName":"x"}]' | Set-Content -LiteralPath $bad
            { New-DefenderDcPolicy -Usb ReadOnly -AllowDeviceFile $bad -OutputPath $TestDrive } |
                Should -Throw -ExpectedMessage '*InstancePathId*'
        }
    }

    Context 'generation' {
        It 'minimal call writes three parseable policy files and returns their paths' {
            $out = Join-Path $TestDrive 'minimal'
            $result = New-DefenderDcPolicy -Usb ReadOnly -OutputPath $out
            $result.GroupsXmlPath       | Should -Be (Join-Path $out 'PolicyGroups.xml')
            $result.AuditRulesXmlPath   | Should -Be (Join-Path $out 'PolicyRules.Audit.xml')
            $result.EnforceRulesXmlPath | Should -Be (Join-Path $out 'PolicyRules.Enforce.xml')
            foreach ($p in $result.GroupsXmlPath, $result.AuditRulesXmlPath, $result.EnforceRulesXmlPath) {
                Test-Path -LiteralPath $p | Should -BeTrue
                { Read-DcPolicyXml -Path $p } | Should -Not -Throw
            }
        }

        It 'writes files without a BOM' {
            $out = Join-Path $TestDrive 'bom'
            $result = New-DefenderDcPolicy -Usb ReadOnly -OutputPath $out
            $bytes = [System.IO.File]::ReadAllBytes($result.GroupsXmlPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse
        }

        It 'merges exceptions from -AllowHardwareId, -AllowDeviceFile, and pipeline, deduped' {
            $out = Join-Path $TestDrive 'merge'
            $file = Join-Path $TestDrive 'devices.json'
            '[{"InstancePathId":"USBSTOR\\DISK\\SER1&0"},{"InstancePathId":"USBSTOR\\DISK\\SER2&0"}]' |
                Set-Content -LiteralPath $file
            $piped = [pscustomobject]@{ InstancePathId = 'USBSTOR\DISK\SER1&0' }   # dupe of file entry
            $result = $piped | New-DefenderDcPolicy -Usb ReadOnly -AllowHardwareId 'HW\1' -AllowDeviceFile $file -OutputPath $out
            $groups = [xml](Get-Content -LiteralPath $result.GroupsXmlPath -Raw)
            $approved = @($groups.Groups.Group) | Where-Object { $_.Name -eq 'Approved devices' }
            @($approved.DescriptorIdList.InstancePathId).Count | Should -Be 2
            @($approved.DescriptorIdList.HardwareId).Count | Should -Be 1
        }

        It 'defaults -OutputPath to the current directory' {
            Push-Location $TestDrive
            try {
                $result = New-DefenderDcPolicy -Optical Block
                $result.GroupsXmlPath | Should -Be (Join-Path (Get-Location).ProviderPath 'PolicyGroups.xml')
            } finally { Pop-Location }
        }

        It 'result object carries the PolicyFiles type name' {
            $result = New-DefenderDcPolicy -Usb Allow -OutputPath (Join-Path $TestDrive 'tn')
            $result.PSObject.TypeNames | Should -Contain 'DefenderDeviceControlUnmanaged.PolicyFiles'
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/New-DefenderDcPolicy.Tests.ps1 -Output Detailed"`
Expected: FAIL — `New-DefenderDcPolicy` file missing.

- [ ] **Step 3: Write the implementation**

```powershell
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
    [CmdletBinding()]
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

        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        $resolvedOut = Convert-Path -LiteralPath $OutputPath

        $groupsPath  = Join-Path $resolvedOut 'PolicyGroups.xml'
        $auditPath   = Join-Path $resolvedOut 'PolicyRules.Audit.xml'
        $enforcePath = Join-Path $resolvedOut 'PolicyRules.Enforce.xml'

        # All three strings are built before any write, so a failure cannot
        # leave a partially-generated policy on disk. WriteAllText emits
        # UTF-8 without BOM (the engine validator rejects BOMs).
        [System.IO.File]::WriteAllText($groupsPath,  $xml.GroupsXml)
        [System.IO.File]::WriteAllText($auditPath,   $xml.AuditRulesXml)
        [System.IO.File]::WriteAllText($enforcePath, $xml.EnforceRulesXml)

        Write-Verbose "Wrote $groupsPath"
        Write-Verbose "Wrote $auditPath"
        Write-Verbose "Wrote $enforcePath"

        [pscustomobject]@{
            PSTypeName          = 'DefenderDeviceControlUnmanaged.PolicyFiles'
            GroupsXmlPath       = $groupsPath
            AuditRulesXmlPath   = $auditPath
            EnforceRulesXmlPath = $enforcePath
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/New-DefenderDcPolicy.Tests.ps1 -Output Detailed"`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/Public/New-DefenderDcPolicy.ps1 src/Tests/Unit/New-DefenderDcPolicy.Tests.ps1
git commit -m "feat: add New-DefenderDcPolicy policy builder cmdlet"
```

---

## Task 4: Private helper `ConvertTo-DcDevice`

Converts one PnP entity (CIM instance, or any object with the same properties — that's what makes it testable) into the module's device record. Returns nothing for device classes we don't track.

**Files:**

- Create: `src/DefenderDeviceControlUnmanaged/Private/ConvertTo-DcDevice.ps1`
- Test: `src/Tests/Unit/ConvertTo-DcDevice.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\ConvertTo-DcDevice.ps1')

    function script:New-FakePnp {
        param($Name, $PNPDeviceID, $PNPClass, $HardwareID)
        [pscustomobject]@{
            Name        = $Name
            PNPDeviceID = $PNPDeviceID
            PNPClass    = $PNPClass
            HardwareID  = $HardwareID
        }
    }
}

Describe 'ConvertTo-DcDevice' {
    It 'classifies USBSTOR instance ids as Usb and extracts the serial' {
        $d = ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Kingston DataTraveler 3.0 USB Device' `
            -PNPDeviceID 'USBSTOR\DISK&VEN_KINGSTON&PROD_DATATRAVELER_3.0&REV_PMAP\E0D55EA574DBF750E97B0A14&0' `
            -PNPClass 'DiskDrive' `
            -HardwareID @('USBSTOR\DiskKingstonDataTraveler_3.0'))
        $d.Class          | Should -Be 'Usb'
        $d.FriendlyName   | Should -Be 'Kingston DataTraveler 3.0 USB Device'
        $d.InstancePathId | Should -Be 'USBSTOR\DISK&VEN_KINGSTON&PROD_DATATRAVELER_3.0&REV_PMAP\E0D55EA574DBF750E97B0A14&0'
        $d.SerialNumber   | Should -Be 'E0D55EA574DBF750E97B0A14'
        $d.HardwareIds    | Should -Contain 'USBSTOR\DiskKingstonDataTraveler_3.0'
    }

    It 'classifies PNPClass CDROM as Optical' {
        (ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'DVD Drive' `
            -PNPDeviceID 'SCSI\CDROM&VEN_X\5&1&0' -PNPClass 'CDROM' -HardwareID @())).Class |
            Should -Be 'Optical'
    }

    It 'classifies PNPClass WPD as Wpd and extracts VID_PID' {
        $d = ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Pixel 8' `
            -PNPDeviceID 'USB\VID_18D1&PID_4EE1\SERIAL123' -PNPClass 'WPD' `
            -HardwareID @('USB\VID_18D1&PID_4EE1&REV_0440'))
        $d.Class  | Should -Be 'Wpd'
        $d.VidPid | Should -Be 'VID_18D1&PID_4EE1'
        $d.SerialNumber | Should -Be 'SERIAL123'
    }

    It 'returns nothing for untracked device classes' {
        ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Intel(R) GPU' `
            -PNPDeviceID 'PCI\VEN_8086&DEV_X\3&1' -PNPClass 'Display' -HardwareID @()) |
            Should -BeNullOrEmpty
    }

    It 'VidPid is null when no VID/PID pattern is present (USBSTOR child nodes)' {
        $d = ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Disk' `
            -PNPDeviceID 'USBSTOR\DISK&VEN_K&PROD_P&REV_1\SER&0' -PNPClass 'DiskDrive' -HardwareID @())
        $d.VidPid | Should -BeNullOrEmpty
    }

    It 'tolerates a missing PNPClass property (strict-mode safe)' {
        $entity = [pscustomobject]@{ Name = 'X'; PNPDeviceID = 'USBSTOR\DISK\S&0'; HardwareID = $null }
        { ConvertTo-DcDevice -PnpEntity $entity } | Should -Not -Throw
    }

    It 'stamps CapturedAt as an ISO-8601 UTC string and tags the type name' {
        $d = ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Disk' `
            -PNPDeviceID 'USBSTOR\DISK\SER&0' -PNPClass 'DiskDrive' -HardwareID @())
        $d.CapturedAt | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        $d.PSObject.TypeNames | Should -Contain 'DefenderDeviceControlUnmanaged.Device'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/ConvertTo-DcDevice.Tests.ps1 -Output Detailed"`
Expected: FAIL — file missing.

- [ ] **Step 3: Write the implementation**

```powershell
function ConvertTo-DcDevice {
    <#
    .SYNOPSIS
        Convert a Win32_PnPEntity instance into the module's device record.
    .DESCRIPTION
        Classifies the entity into the device classes this module tracks
        (Usb removable storage, Wpd, Optical) and extracts the Device
        Control-usable descriptors. Returns nothing for untracked classes,
        so callers can pipe a full PnP enumeration through it. Accepts any
        object with Name/PNPDeviceID/PNPClass/HardwareID properties (tests
        pass fakes).
    .PARAMETER PnpEntity
        A Win32_PnPEntity CIM instance or shape-compatible object.
    .EXAMPLE
        Get-CimInstance Win32_PnPEntity | ForEach-Object { ConvertTo-DcDevice -PnpEntity $_ }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $PnpEntity
    )

    Set-StrictMode -Version Latest

    $pnpId = [string]$PnpEntity.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($pnpId)) { return }

    $pnpClassProp = $PnpEntity.PSObject.Properties['PNPClass']
    $pnpClass = if ($null -ne $pnpClassProp) { [string]$pnpClassProp.Value } else { '' }

    # USBSTOR prefix beats PNPClass: removable disks report PNPClass DiskDrive.
    $class = if ($pnpId -like 'USBSTOR\*') { 'Usb' }
             elseif ($pnpClass -eq 'CDROM') { 'Optical' }
             elseif ($pnpClass -eq 'WPD')   { 'Wpd' }
             else { $null }
    if ($null -eq $class) { return }

    $hardwareIdsProp = $PnpEntity.PSObject.Properties['HardwareID']
    $hardwareIds = if ($null -ne $hardwareIdsProp -and $null -ne $hardwareIdsProp.Value) {
        @($hardwareIdsProp.Value | ForEach-Object { [string]$_ })
    } else { @() }

    # VID/PID lives on the USB device node; USBSTOR children often lack it.
    $vidPid = $null
    foreach ($candidate in (@($pnpId) + $hardwareIds)) {
        if ($candidate -match '(VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4})') {
            $vidPid = $Matches[1].ToUpperInvariant()
            break
        }
    }

    # Instance path convention: serial is the last path segment, before any
    # '&N' disambiguator (e.g. ...\E0D55EA574DBF750E97B0A14&0).
    $serial = ($pnpId.Split('\')[-1]).Split('&')[0]

    [pscustomobject]@{
        PSTypeName     = 'DefenderDeviceControlUnmanaged.Device'
        FriendlyName   = [string]$PnpEntity.Name
        Class          = $class
        InstancePathId = $pnpId
        HardwareIds    = $hardwareIds
        VidPid         = $vidPid
        SerialNumber   = $serial
        CapturedAt     = (Get-Date).ToUniversalTime().ToString('o')
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/ConvertTo-DcDevice.Tests.ps1 -Output Detailed"`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/Private/ConvertTo-DcDevice.ps1 src/Tests/Unit/ConvertTo-DcDevice.Tests.ps1
git commit -m "feat: add ConvertTo-DcDevice PnP classification helper"
```

---

## Task 5: Private helpers `Get-DcPnpEntity` + `Add-DcDeviceRecord`

A thin mockable CIM wrapper (same pattern as the existing `Get-DcComputerStatus` wrapping `Get-MpComputerStatus`), and the JSON append/dedupe writer for `-OutFile`.

**Files:**

- Create: `src/DefenderDeviceControlUnmanaged/Private/Get-DcPnpEntity.ps1`
- Create: `src/DefenderDeviceControlUnmanaged/Private/Add-DcDeviceRecord.ps1`
- Test: `src/Tests/Unit/Add-DcDeviceRecord.Tests.ps1`

- [ ] **Step 1: Write the failing test (Add-DcDeviceRecord only — Get-DcPnpEntity is a one-line CIM passthrough, covered via mocks in Task 6)**

```powershell
BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\Add-DcDeviceRecord.ps1')

    function script:New-Record([string] $Id) {
        [pscustomobject]@{ FriendlyName = 'X'; Class = 'Usb'; InstancePathId = $Id }
    }
}

Describe 'Add-DcDeviceRecord' {
    It 'creates the file as a JSON array on first write' {
        $path = Join-Path $TestDrive 'a.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        $parsed = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
        $parsed.Count | Should -Be 1
        $parsed[0].InstancePathId | Should -Be 'USBSTOR\1'
    }

    It 'appends new devices and keeps existing ones' {
        $path = Join-Path $TestDrive 'b.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\2')
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count | Should -Be 2
    }

    It 'dedupes by InstancePathId' {
        $path = Join-Path $TestDrive 'c.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count | Should -Be 1
    }

    It 'single record still serializes as a JSON array (PS 5.1 unrolling guard)' {
        $path = Join-Path $TestDrive 'd.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        (Get-Content -LiteralPath $path -Raw).TrimStart() | Should -Match '^\['
    }

    It 'throws a clear error when the existing file is not valid JSON' {
        $path = Join-Path $TestDrive 'e.json'
        'not json' | Set-Content -LiteralPath $path
        { Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1') } |
            Should -Throw -ExpectedMessage '*not valid JSON*'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/Add-DcDeviceRecord.Tests.ps1 -Output Detailed"`
Expected: FAIL — file missing.

- [ ] **Step 3: Write both implementations**

`Get-DcPnpEntity.ps1`:

```powershell
function Get-DcPnpEntity {
    <#
    .SYNOPSIS
        Enumerate Win32_PnPEntity instances (thin Get-CimInstance wrapper).
    .DESCRIPTION
        Exists so Get-DefenderDcDevice tests can mock PnP enumeration without
        CIM, mirroring how Get-DcComputerStatus wraps Get-MpComputerStatus.
    .EXAMPLE
        Get-DcPnpEntity
    #>
    [CmdletBinding()]
    param()

    Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
}
```

`Add-DcDeviceRecord.ps1`:

```powershell
function Add-DcDeviceRecord {
    <#
    .SYNOPSIS
        Append a captured device record to a JSON array file, deduped by
        InstancePathId.
    .DESCRIPTION
        Read-modify-write per device so an interrupted watch session (Ctrl+C)
        keeps everything captured so far. The file is the
        New-DefenderDcPolicy -AllowDeviceFile input format.
    .PARAMETER Path
        JSON file path. Created on first write.
    .PARAMETER Device
        A device record from ConvertTo-DcDevice.
    .EXAMPLE
        Add-DcDeviceRecord -Path .\approved.json -Device $device
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [pscustomobject] $Device
    )

    Set-StrictMode -Version Latest

    $existing = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $raw = Get-Content -LiteralPath $Path -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try { $existing = @($raw | ConvertFrom-Json) } catch {
                throw "Add-DcDeviceRecord: existing file is not valid JSON: $Path ($($_.Exception.Message))"
            }
        }
    }

    foreach ($e in $existing) {
        $prop = $e.PSObject.Properties['InstancePathId']
        if ($null -ne $prop -and [string]$prop.Value -eq [string]$Device.InstancePathId) { return }
    }

    $all = @($existing) + @($Device)
    # -InputObject (not pipeline) so a single element still serializes as [ ].
    $json = ConvertTo-Json -InputObject @($all) -Depth 5
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/Add-DcDeviceRecord.Tests.ps1 -Output Detailed"`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/Private/Get-DcPnpEntity.ps1 src/DefenderDeviceControlUnmanaged/Private/Add-DcDeviceRecord.ps1 src/Tests/Unit/Add-DcDeviceRecord.Tests.ps1
git commit -m "feat: add Get-DcPnpEntity and Add-DcDeviceRecord helpers"
```

---

## Task 6: Public cmdlet `Get-DefenderDcDevice` — snapshot mode + `-OutFile`

**Files:**

- Create: `src/DefenderDeviceControlUnmanaged/Public/Get-DefenderDcDevice.ps1`
- Test: `src/Tests/Unit/Get-DefenderDcDevice.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\ConvertTo-DcDevice.ps1')
    . (Join-Path $ModuleRoot 'Private\Get-DcPnpEntity.ps1')
    . (Join-Path $ModuleRoot 'Private\Add-DcDeviceRecord.ps1')
    . (Join-Path $ModuleRoot 'Private\Test-DcIsWindows.ps1')
    . (Join-Path $ModuleRoot 'Public\Get-DefenderDcDevice.ps1')

    $script:FakeUsb = [pscustomobject]@{
        Name        = 'Kingston DataTraveler 3.0 USB Device'
        PNPDeviceID = 'USBSTOR\DISK&VEN_KINGSTON&PROD_DT&REV_1\SER123&0'
        PNPClass    = 'DiskDrive'
        HardwareID  = @('USBSTOR\DiskKingstonDT')
    }
    $script:FakeGpu = [pscustomobject]@{
        Name        = 'Intel GPU'
        PNPDeviceID = 'PCI\VEN_8086&DEV_1\3&1'
        PNPClass    = 'Display'
        HardwareID  = @()
    }
}

Describe 'Get-DefenderDcDevice (snapshot)' {
    BeforeEach {
        # Dev box is macOS; the cmdlet's platform gate must be mocked away.
        Mock Test-DcIsWindows { $true }
    }

    It 'returns only tracked-class devices' {
        Mock Get-DcPnpEntity { @($FakeUsb, $FakeGpu) }
        $devices = @(Get-DefenderDcDevice)
        $devices.Count | Should -Be 1
        $devices[0].Class | Should -Be 'Usb'
        $devices[0].InstancePathId | Should -Be 'USBSTOR\DISK&VEN_KINGSTON&PROD_DT&REV_1\SER123&0'
    }

    It 'writes captured devices to -OutFile' {
        Mock Get-DcPnpEntity { @($FakeUsb) }
        $path = Join-Path $TestDrive 'snap.json'
        Get-DefenderDcDevice -OutFile $path | Out-Null
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count | Should -Be 1
    }

    It 'rejects -TimeoutSeconds without -Watch' {
        { Get-DefenderDcDevice -TimeoutSeconds 5 } |
            Should -Throw -ExpectedMessage '*-TimeoutSeconds requires -Watch*'
    }

    It 'has populated comment-based help (SYNOPSIS + EXAMPLE)' {
        $help = Get-Help Get-DefenderDcDevice -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterThan 0
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/Get-DefenderDcDevice.Tests.ps1 -Output Detailed"`
Expected: FAIL — file missing.

- [ ] **Step 3: Write the implementation (snapshot only; `-Watch` throws "not implemented" until Task 7)**

Two files. First the platform gate as its own mockable helper (PS 5.1 has no
`$IsWindows` automatic variable, and unit tests on the macOS dev box must be
able to mock the check away):

`src/DefenderDeviceControlUnmanaged/Private/Test-DcIsWindows.ps1`:

```powershell
function Test-DcIsWindows {
    <#
    .SYNOPSIS
        True when running on Windows (PS 5.1 or PowerShell 7+).
    .DESCRIPTION
        PS 5.1 has no automatic $IsWindows variable; the short-circuit -or
        only evaluates $IsWindows on Core, keeping StrictMode happy. Separate
        function so unit tests can mock the platform.
    .EXAMPLE
        Test-DcIsWindows
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows
}
```

Then the cmdlet, `src/DefenderDeviceControlUnmanaged/Public/Get-DefenderDcDevice.ps1`:

```powershell
function Get-DefenderDcDevice {
    <#
    .SYNOPSIS
        Capture the hardware identifiers of removable, WPD, and optical
        devices for Device Control policy crafting.

    .DESCRIPTION
        Snapshot mode (default) enumerates currently-connected devices in the
        classes this module tracks (USB removable storage, WPD/MTP, optical)
        and emits one record per device with its Device Control-usable
        descriptors: InstancePathId (serial-specific), HardwareIds
        (model-wide), VID/PID, serial, friendly name.

        -Watch subscribes to PnP device-arrival events: plug devices in one by
        one and each is emitted as it arrives, until Ctrl+C or
        -TimeoutSeconds. Read-only PnP queries; no elevation required.

        -OutFile appends each record to a JSON array file as it is captured
        (deduped by InstancePathId), which is exactly the
        New-DefenderDcPolicy -AllowDeviceFile input.

    .PARAMETER Watch
        Subscribe to device-arrival events and emit devices as they are
        plugged in, instead of a one-shot snapshot.

    .PARAMETER TimeoutSeconds
        Stop watching after this many seconds. Only valid with -Watch.
        Without it, -Watch runs until Ctrl+C.

    .PARAMETER OutFile
        JSON file to append captured devices to (created on first capture).

    .EXAMPLE
        Get-DefenderDcDevice

        List currently-connected removable/WPD/optical devices.

    .EXAMPLE
        Get-DefenderDcDevice -Watch -OutFile .\approved.json

        Plug approved sticks in one by one; each is printed and appended to
        approved.json. Ctrl+C when done.

    .EXAMPLE
        Get-DefenderDcDevice -Watch -TimeoutSeconds 60 |
            New-DefenderDcPolicy -Usb ReadOnly -OutputPath .\policy\

        Capture for one minute, then craft a policy exempting what arrived.

    .LINK
        https://lukeevanstech.github.io/defender-device-control-unmanaged/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch] $Watch,

        [Alias('Timeout')]
        [int] $TimeoutSeconds,

        [string] $OutFile
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($TimeoutSeconds -and -not $Watch) {
        throw 'Get-DefenderDcDevice: -TimeoutSeconds requires -Watch.'
    }

    if (-not (Test-DcIsWindows)) {
        throw 'Get-DefenderDcDevice: requires Windows (CIM/PnP device enumeration).'
    }

    if (-not $Watch) {
        foreach ($entity in @(Get-DcPnpEntity)) {
            $device = ConvertTo-DcDevice -PnpEntity $entity
            if ($null -eq $device) { continue }
            if ($OutFile) { Add-DcDeviceRecord -Path $OutFile -Device $device }
            $device
        }
        return
    }

    throw 'Get-DefenderDcDevice: -Watch is not implemented yet.'
}
```

(The `-TimeoutSeconds requires -Watch` validation deliberately runs before the
platform gate so it behaves identically everywhere; the test file's
`BeforeEach` mock of `Test-DcIsWindows` covers the device-returning tests.)

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/Get-DefenderDcDevice.Tests.ps1 -Output Detailed"`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/Public/Get-DefenderDcDevice.ps1 src/DefenderDeviceControlUnmanaged/Private/Test-DcIsWindows.ps1 src/Tests/Unit/Get-DefenderDcDevice.Tests.ps1
git commit -m "feat: add Get-DefenderDcDevice snapshot mode"
```

---

## Task 7: `Get-DefenderDcDevice -Watch` (live capture)

**Files:**

- Modify: `src/DefenderDeviceControlUnmanaged/Public/Get-DefenderDcDevice.ps1` (replace the `throw '... not implemented'` line)
- Modify: `src/Tests/Unit/Get-DefenderDcDevice.Tests.ps1` (add a Describe block)

- [ ] **Step 1: Write the failing test (append to the existing test file)**

```powershell
Describe 'Get-DefenderDcDevice (-Watch)' {
    BeforeEach {
        Mock Test-DcIsWindows { $true }
        Mock Register-CimIndicationEvent { }
        Mock Unregister-Event { }
        Mock Get-Event { @() }
        Mock Remove-Event { }
    }

    It 'emits a device per arrival event and stops at the timeout' {
        $script:waitCalls = 0
        Mock Wait-Event {
            $script:waitCalls++
            if ($script:waitCalls -eq 1) {
                [pscustomobject]@{
                    EventIdentifier = 11
                    SourceEventArgs = [pscustomobject]@{
                        NewEvent = [pscustomobject]@{ TargetInstance = $FakeUsb }
                    }
                }
            }
            # subsequent calls: $null (no event within the 1s poll)
        }

        $devices = @(Get-DefenderDcDevice -Watch -TimeoutSeconds 2)
        $devices.Count | Should -Be 1
        $devices[0].Class | Should -Be 'Usb'
        Should -Invoke Register-CimIndicationEvent -Times 1 -Exactly
        Should -Invoke Remove-Event -Times 1 -Exactly
    }

    It 'always unregisters the event subscription (finally)' {
        Mock Wait-Event { $null }
        Get-DefenderDcDevice -Watch -TimeoutSeconds 1 | Out-Null
        Should -Invoke Unregister-Event -Times 1 -Exactly
    }

    It 'appends watched devices to -OutFile' {
        $script:waitCalls2 = 0
        Mock Wait-Event {
            $script:waitCalls2++
            if ($script:waitCalls2 -eq 1) {
                [pscustomobject]@{
                    EventIdentifier = 12
                    SourceEventArgs = [pscustomobject]@{
                        NewEvent = [pscustomobject]@{ TargetInstance = $FakeUsb }
                    }
                }
            }
        }
        $path = Join-Path $TestDrive 'watch.json'
        Get-DefenderDcDevice -Watch -TimeoutSeconds 2 -OutFile $path | Out-Null
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count | Should -Be 1
    }

    It 'ignores arrival events for untracked device classes' {
        $script:waitCalls3 = 0
        Mock Wait-Event {
            $script:waitCalls3++
            if ($script:waitCalls3 -eq 1) {
                [pscustomobject]@{
                    EventIdentifier = 13
                    SourceEventArgs = [pscustomobject]@{
                        NewEvent = [pscustomobject]@{ TargetInstance = $FakeGpu }
                    }
                }
            }
        }
        @(Get-DefenderDcDevice -Watch -TimeoutSeconds 2).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/Get-DefenderDcDevice.Tests.ps1 -Output Detailed"`
Expected: the 4 new tests FAIL with `-Watch is not implemented yet`; the snapshot tests still PASS.

- [ ] **Step 3: Implement watch mode**

Replace `throw 'Get-DefenderDcDevice: -Watch is not implemented yet.'` with:

```powershell
    $sourceId = "DdcuDeviceWatch-$([guid]::NewGuid().ToString('N'))"
    $query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_PnPEntity'"
    Register-CimIndicationEvent -Query $query -SourceIdentifier $sourceId | Out-Null
    Write-Verbose 'Watching for device arrivals. Plug devices in one by one; Ctrl+C to stop.'

    try {
        $deadline = if ($TimeoutSeconds) { (Get-Date).AddSeconds($TimeoutSeconds) } else { [datetime]::MaxValue }
        while ((Get-Date) -lt $deadline) {
            # 1s poll keeps Ctrl+C responsive between events.
            $evt = Wait-Event -SourceIdentifier $sourceId -Timeout 1
            if ($null -eq $evt) { continue }
            Remove-Event -EventIdentifier $evt.EventIdentifier
            $device = ConvertTo-DcDevice -PnpEntity $evt.SourceEventArgs.NewEvent.TargetInstance
            if ($null -eq $device) { continue }
            if ($OutFile) { Add-DcDeviceRecord -Path $OutFile -Device $device }
            $device
        }
    }
    finally {
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/Get-DefenderDcDevice.Tests.ps1 -Output Detailed"`
Expected: PASS (8 tests). Note: the timeout tests take ~2-3 s of wall clock each (1 s poll loop) — that's expected.

- [ ] **Step 5: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/Public/Get-DefenderDcDevice.ps1 src/Tests/Unit/Get-DefenderDcDevice.Tests.ps1
git commit -m "feat: add Get-DefenderDcDevice -Watch live capture"
```

---

## Task 8: `Set-DefenderDcPolicy` pipeline support

Accept the builder's result object by property name; `-Mode` selects between the piped audit/enforce rules paths. An explicit `-RulesXmlPath` always wins. The function body is an implicit `end` block — fine here, because exactly one `PolicyFiles` object is ever piped; document that in a comment.

**Files:**

- Modify: `src/DefenderDeviceControlUnmanaged/Public/Set-DefenderDcPolicy.ps1`
- Modify: `src/Tests/Unit/Set-DefenderDcPolicy.Tests.ps1` (append a Context)

- [ ] **Step 1: Write the failing test (append inside the existing `Describe 'Set-DefenderDcPolicy'`)**

```powershell
    Context 'pipeline input from New-DefenderDcPolicy' {
        It 'GroupsXmlPath / AuditRulesXmlPath / EnforceRulesXmlPath accept pipeline-by-property-name' {
            $cmd = Get-Command Set-DefenderDcPolicy
            foreach ($name in 'GroupsXmlPath','AuditRulesXmlPath','EnforceRulesXmlPath') {
                $attr = $cmd.Parameters[$name].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
                $attr.ValueFromPipelineByPropertyName | Should -BeTrue -Because $name
            }
        }

        It 'Mode Audit consumes the piped AuditRulesXmlPath' {
            # $TestDrive does not flow into InModuleScope; pass it explicitly.
            InModuleScope DefenderDeviceControlUnmanaged -Parameters @{ TestRoot = $TestDrive } {
                param($TestRoot)
                Mock Test-DcIsElevated { $true }
                Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true; AMEngineVersion = '0.0'; IsTamperProtected = $false } }
                Mock Start-DcTranscript { Join-Path $TestRoot 'fake.transcript.txt' }
                Mock Stop-Transcript { }
                Mock Test-DefenderDcPolicyXml { $true }
                Mock Remove-DcPolicy { }
                Mock Get-DcRegistryManifest { @() }
                Mock Invoke-DcRegistryWrites { }
                Mock Update-MpSignature { }

                $groups  = Join-Path $TestRoot 'PolicyGroups.xml'
                $audit   = Join-Path $TestRoot 'PolicyRules.Audit.xml'
                $enforce = Join-Path $TestRoot 'PolicyRules.Enforce.xml'
                '<Groups></Groups>' | Set-Content -LiteralPath $groups
                '<PolicyRules></PolicyRules>' | Set-Content -LiteralPath $audit
                '<PolicyRules></PolicyRules>' | Set-Content -LiteralPath $enforce

                $files = [pscustomobject]@{
                    GroupsXmlPath       = $groups
                    AuditRulesXmlPath   = $audit
                    EnforceRulesXmlPath = $enforce
                }
                $files | Set-DefenderDcPolicy -Mode Audit -SkipGpUpdate -Confirm:$false

                Should -Invoke Get-DcRegistryManifest -Times 1 -Exactly -ParameterFilter {
                    $RulesXmlPath -like '*PolicyRules.Audit.xml' -and $GroupsXmlPath -like '*PolicyGroups.xml'
                }
            }
        }

        It 'Mode Enforce consumes the piped EnforceRulesXmlPath' {
            InModuleScope DefenderDeviceControlUnmanaged -Parameters @{ TestRoot = $TestDrive } {
                param($TestRoot)
                Mock Test-DcIsElevated { $true }
                Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true; AMEngineVersion = '0.0'; IsTamperProtected = $false } }
                Mock Start-DcTranscript { Join-Path $TestRoot 'fake.transcript.txt' }
                Mock Stop-Transcript { }
                Mock Test-DefenderDcPolicyXml { $true }
                Mock Remove-DcPolicy { }
                Mock Get-DcRegistryManifest { @() }
                Mock Invoke-DcRegistryWrites { }
                Mock Update-MpSignature { }

                $groups  = Join-Path $TestRoot 'g.xml'
                $audit   = Join-Path $TestRoot 'a.xml'
                $enforce = Join-Path $TestRoot 'e.xml'
                '<Groups></Groups>' | Set-Content -LiteralPath $groups
                '<PolicyRules></PolicyRules>' | Set-Content -LiteralPath $audit
                '<PolicyRules></PolicyRules>' | Set-Content -LiteralPath $enforce

                [pscustomobject]@{
                    GroupsXmlPath       = $groups
                    AuditRulesXmlPath   = $audit
                    EnforceRulesXmlPath = $enforce
                } | Set-DefenderDcPolicy -Mode Enforce -SkipGpUpdate -Confirm:$false

                Should -Invoke Get-DcRegistryManifest -Times 1 -Exactly -ParameterFilter {
                    $RulesXmlPath -like '*e.xml'
                }
            }
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/Set-DefenderDcPolicy.Tests.ps1 -Output Detailed"`
Expected: the 3 new tests FAIL (parameters missing / default starter rules path used); all pre-existing tests still PASS.

- [ ] **Step 3: Implement**

In `Set-DefenderDcPolicy.ps1`, change the param block entries:

```powershell
        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $GroupsXmlPath,

        [string] $RulesXmlPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $AuditRulesXmlPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $EnforceRulesXmlPath,
```

(`-RulesXmlPath` deliberately does NOT bind from the pipeline — it stays the explicit override.)

Then, immediately BEFORE the existing default-fallback lines

```powershell
        $defaultPolicyDir = Join-Path $PSScriptRoot '..\policy'
```

insert:

```powershell
        # Pipeline support: New-DefenderDcPolicy emits one PolicyFiles object
        # with both rules paths; -Mode picks the right one. Explicit
        # -RulesXmlPath always wins. (Single piped object, so the implicit
        # end-block body sees its bound properties — no process block needed.)
        if (-not $RulesXmlPath) {
            if ($Mode -eq 'Audit' -and $AuditRulesXmlPath)     { $RulesXmlPath = $AuditRulesXmlPath }
            if ($Mode -eq 'Enforce' -and $EnforceRulesXmlPath) { $RulesXmlPath = $EnforceRulesXmlPath }
        }
```

Add comment-based help for the two new parameters (after the `.PARAMETER RulesXmlPath` block):

```text
.PARAMETER AuditRulesXmlPath
    Pipeline-bound (by property name) audit rules path from
    New-DefenderDcPolicy. Used when -Mode Audit and no explicit -RulesXmlPath.

.PARAMETER EnforceRulesXmlPath
    Pipeline-bound (by property name) enforce rules path from
    New-DefenderDcPolicy. Used when -Mode Enforce and no explicit -RulesXmlPath.
```

And add an example to the help:

```text
.EXAMPLE
    New-DefenderDcPolicy -Usb ReadOnly -OutputPath .\policy\ | Set-DefenderDcPolicy -Mode Audit

    Craft and apply a custom policy in one pipeline.
```

- [ ] **Step 4: Run the full unit suite (this change touches a core cmdlet)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit -Output Detailed"`
Expected: ALL PASS. (The two new public function files exist, but the psd1 `FunctionsToExport` list still names only the original 6, and a manifest export list filters what the psm1 exports — so `ExportedFunctions.Tests.ps1` still sees exactly 6 until Task 9 updates both sides.)

- [ ] **Step 5: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/Public/Set-DefenderDcPolicy.ps1 src/Tests/Unit/Set-DefenderDcPolicy.Tests.ps1
git commit -m "feat: Set-DefenderDcPolicy accepts New-DefenderDcPolicy pipeline output"
```

---

## Task 9: Module manifest, exported-surface tests, version, changelog

**Files:**

- Modify: `src/DefenderDeviceControlUnmanaged/DefenderDeviceControlUnmanaged.psd1`
- Modify: `src/Tests/Unit/ExportedFunctions.Tests.ps1`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the export-surface test (failing first)**

In `ExportedFunctions.Tests.ps1`, change the count and names:

```powershell
    It 'exports exactly 8 cmdlets' {
        $cmds = Get-Command -Module DefenderDeviceControlUnmanaged
        $cmds.Count | Should -Be 8
    }

    It 'exports the canonical 8 cmdlet names' {
        $expected = @(
            'Get-DefenderDcDevice',
            'Get-DefenderDcPolicy',
            'Invoke-DefenderDcOnboarding',
            'Invoke-DefenderDcUsbTest',
            'New-DefenderDcPolicy',
            'Set-DefenderDcPolicy',
            'Test-DefenderDcPolicy',
            'Test-DefenderDcPolicyXml'
        )
        $actual = (Get-Command -Module DefenderDeviceControlUnmanaged).Name | Sort-Object
        $actual | Should -Be ($expected | Sort-Object)
    }
```

Also extend the private-helper leak test with the new helpers:

```powershell
        $cmds.Name | Should -Not -Contain 'New-DcDeterministicGuid'
        $cmds.Name | Should -Not -Contain 'ConvertTo-DcPolicyXml'
        $cmds.Name | Should -Not -Contain 'ConvertTo-DcDevice'
        $cmds.Name | Should -Not -Contain 'Get-DcPnpEntity'
        $cmds.Name | Should -Not -Contain 'Add-DcDeviceRecord'
        $cmds.Name | Should -Not -Contain 'Test-DcIsWindows'
```

- [ ] **Step 2: Run to verify the manifest-driven assertions fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit/ExportedFunctions.Tests.ps1 -Output Detailed"`
Expected: the count and name-list tests FAIL — the manifest `FunctionsToExport` still lists 6, and a manifest export list filters the psm1's exports down to those 6, so the module surfaces 6 where the updated tests now demand 8.

- [ ] **Step 3: Update the manifest**

In `DefenderDeviceControlUnmanaged.psd1`:

```powershell
    ModuleVersion     = '1.1.0'
```

```powershell
    FunctionsToExport = @(
        'Get-DefenderDcDevice',
        'Get-DefenderDcPolicy',
        'Invoke-DefenderDcOnboarding',
        'Invoke-DefenderDcUsbTest',
        'New-DefenderDcPolicy',
        'Set-DefenderDcPolicy',
        'Test-DefenderDcPolicy',
        'Test-DefenderDcPolicyXml'
    )
```

- [ ] **Step 4: Update CHANGELOG.md** — under `## [Unreleased]` add:

```markdown
## [1.1.0] - unreleased

### Added

- `New-DefenderDcPolicy`: craft custom Device Control policy XML from per-class
  restriction flags (`-Usb ReadOnly,DenyExecute`, `-Wpd ReadOnly`,
  `-Optical Block`, `Allow`) with approved-device exceptions
  (`-AllowHardwareId`, `-AllowDeviceFile`, pipeline). Emits the standard
  three-file shape (Groups + Audit/Enforce rules) with deterministic GUIDs so
  regeneration is byte-identical.
- `Get-DefenderDcDevice`: capture hardware identifiers of connected (or, with
  `-Watch`, newly plugged-in) USB/WPD/optical devices; `-OutFile` writes the
  JSON device list `New-DefenderDcPolicy -AllowDeviceFile` consumes.
- `Set-DefenderDcPolicy` accepts `New-DefenderDcPolicy` output from the
  pipeline; `-Mode` selects the audit or enforce rules file.
```

(Keep the empty `## [Unreleased]` heading above it.)

- [ ] **Step 5: Run the FULL unit suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit -Output Detailed"`
Expected: ALL PASS, including the help-coverage test (`every exported cmdlet has comment-based help`) now covering the two new cmdlets.

- [ ] **Step 6: Commit**

```bash
git add src/DefenderDeviceControlUnmanaged/DefenderDeviceControlUnmanaged.psd1 src/Tests/Unit/ExportedFunctions.Tests.ps1 CHANGELOG.md
git commit -m "feat: export New-DefenderDcPolicy and Get-DefenderDcDevice, bump to 1.1.0"
```

---

## Task 10: Examples, docs pages, nav

**Files:**

- Create: `src/DefenderDeviceControlUnmanaged/examples/Capture-Approved-Devices.ps1`
- Create: `src/DefenderDeviceControlUnmanaged/examples/Craft-Custom-Policy.ps1`
- Create: `docs/docs/howto/craft-custom-policies.md`
- Create: `docs/docs/reference/cmdlets/New-DefenderDcPolicy.md`
- Create: `docs/docs/reference/cmdlets/Get-DefenderDcDevice.md`
- Modify: `docs/zensical.toml` (nav)

- [ ] **Step 1: Write the example scripts** (match existing examples: tiny, top-level, `#Requires` only where needed — the builder/capture need no elevation)

`Capture-Approved-Devices.ps1`:

```powershell
Import-Module (Join-Path $PSScriptRoot '..\DefenderDeviceControlUnmanaged.psd1') -Force
# Plug approved devices in one by one; Ctrl+C when done.
Get-DefenderDcDevice -Watch -OutFile (Join-Path $PSScriptRoot 'approved.json')
```

`Craft-Custom-Policy.ps1`:

```powershell
#Requires -RunAsAdministrator
Import-Module (Join-Path $PSScriptRoot '..\DefenderDeviceControlUnmanaged.psd1') -Force
# USB read-only + no execute, WPD read-only, optical blocked; devices captured
# by Capture-Approved-Devices.ps1 are exempt. Applied in Audit mode first.
$approved = Join-Path $PSScriptRoot 'approved.json'
$splat = @{ Usb = 'ReadOnly','DenyExecute'; Wpd = 'ReadOnly'; Optical = 'Block'; OutputPath = Join-Path $PSScriptRoot 'custom-policy' }
if (Test-Path $approved) { $splat.AllowDeviceFile = $approved }
New-DefenderDcPolicy @splat | Set-DefenderDcPolicy -Mode Audit
Test-DefenderDcPolicy -ExpectMode Audit
```

- [ ] **Step 2: Write `docs/docs/howto/craft-custom-policies.md`**

````markdown
# Craft custom policies

Build a Device Control policy from parameters instead of hand-editing XML,
with specific approved devices exempted.

## 1. Capture the devices you want to approve

No elevation needed — these are read-only PnP queries.

```powershell
Get-DefenderDcDevice -Watch -OutFile .\approved.json
```
````

Plug each approved device in; every arrival prints its identifiers
(`InstancePathId`, `HardwareIds`, VID/PID, serial) and appends to
`approved.json`. ++ctrl+c++ when done. Without `-Watch` you get a snapshot of
currently-connected devices instead.

## 2. Craft the policy

```powershell
New-DefenderDcPolicy -Usb ReadOnly,DenyExecute -Wpd ReadOnly -Optical Block `
    -AllowDeviceFile .\approved.json -OutputPath .\policy\
```

Restriction flags per class (`-Usb`, `-Wpd`, `-Optical`):

| Flag          | Effect                                            |
| ------------- | ------------------------------------------------- |
| `ReadOnly`    | Deny write                                        |
| `DenyExecute` | Deny execute (combinable with `ReadOnly`)         |
| `Block`       | Deny read+write+execute (exclusive)               |
| `Allow`       | No restriction, audit visibility only (exclusive) |

This writes the same three-file shape the module ships — `PolicyGroups.xml`,
`PolicyRules.Audit.xml`, `PolicyRules.Enforce.xml` — so switching from audit
to enforce later is a one-flag change. Approved devices land in an
"Approved devices" group referenced from every rule's `ExcludedIdList`:
they keep full access.

GUIDs are deterministic: regenerate the same policy and the XML is
byte-identical (clean git diffs).

## 3. Apply it

```powershell
# pipeline (the -Mode flag picks the audit or enforce rules file)
New-DefenderDcPolicy -Usb ReadOnly -OutputPath .\policy\ |
    Set-DefenderDcPolicy -Mode Audit

# or explicit paths
Set-DefenderDcPolicy -Mode Enforce -GroupsXmlPath .\policy\PolicyGroups.xml `
    -RulesXmlPath .\policy\PolicyRules.Enforce.xml
```

Validate first without applying: `Test-DefenderDcPolicyXml -Path .\policy\PolicyGroups.xml -Kind Groups`.

## Matching semantics

- Devices captured by `Get-DefenderDcDevice` are exempted by
  **InstancePathId** — serial-specific, approves _that_ stick.
- Strings passed to `-AllowHardwareId` become **HardwareId** descriptors —
  model-wide, approves every device of that model.

- [ ] **Step 3: Write the two cmdlet reference pages** (platyPS layout, matching `docs/docs/reference/cmdlets/Get-DefenderDcPolicy.md`: H1 name, `## SYNOPSIS`, `## SYNTAX` fenced block, `## DESCRIPTION`, `## EXAMPLES` with `### EXAMPLE n`, `## PARAMETERS` with per-parameter yaml blocks, `## INPUTS`/`## OUTPUTS`/`## NOTES`/`## RELATED LINKS`).
      Derive SYNOPSIS/DESCRIPTION/EXAMPLES verbatim from the comment-based help written in Tasks 3 and 6; document every parameter
      (`-Usb`, `-Wpd`, `-Optical`, `-AllowHardwareId`, `-AllowDevice`, `-AllowDeviceFile`, `-OutputPath`, `-PolicyName` / `-Watch`, `-TimeoutSeconds`, `-OutFile`) with Type, Required, Default value, and Accept pipeline input flags consistent with the implementations.

- [ ] **Step 4: Add nav entries in `docs/zensical.toml`**

In the `How-to` list, after the `Extend device categories` line:

```toml
    { "Craft custom policies" = "howto/craft-custom-policies.md" },
```

In the `Cmdlets` list, after the `Set-DefenderDcPolicy` line:

```toml
      { "New-DefenderDcPolicy" = "reference/cmdlets/New-DefenderDcPolicy.md" },
      { "Get-DefenderDcDevice" = "reference/cmdlets/Get-DefenderDcDevice.md" },
```

- [ ] **Step 5: Build the docs site locally to verify nav + pages render**

Run: `cd docs && uvx --from zensical zensical build 2>&1 | tail -5` (or `pip install -r requirements.txt && zensical build` — match whatever `.github/workflows/docs.yml` runs).
Expected: build succeeds, no missing-page warnings for the three new entries.

- [ ] **Step 6: Run the full unit suite once more, then commit**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit -Output Detailed"`
Expected: ALL PASS.

```bash
git add src/DefenderDeviceControlUnmanaged/examples/Capture-Approved-Devices.ps1 src/DefenderDeviceControlUnmanaged/examples/Craft-Custom-Policy.ps1 docs/docs/howto/craft-custom-policies.md docs/docs/reference/cmdlets/New-DefenderDcPolicy.md docs/docs/reference/cmdlets/Get-DefenderDcDevice.md docs/zensical.toml
git commit -m "docs: custom policy crafting guide, cmdlet references, examples"
```

---

## Verification checklist (after all tasks)

- [ ] `pwsh -NoProfile -Command "Invoke-Pester -Path src/Tests/Unit -Output Detailed"` — all green.
- [ ] `Import-Module ./src/DefenderDeviceControlUnmanaged/DefenderDeviceControlUnmanaged.psd1 -Force; Get-Command -Module DefenderDeviceControlUnmanaged` — 8 cmdlets.
- [ ] Smoke the builder end-to-end locally (works on macOS):
      `New-DefenderDcPolicy -Usb ReadOnly,DenyExecute -Wpd ReadOnly -Optical Block -AllowHardwareId 'USBSTOR\DiskKingston' -OutputPath /tmp/ddcu-smoke -Verbose` then eyeball the three XMLs against the starter files' shape.
- [ ] On a Windows box (manual, post-merge): `Get-DefenderDcDevice -Watch -OutFile approved.json`, plug a stick in, confirm capture; `New-DefenderDcPolicy ... | Set-DefenderDcPolicy -Mode Audit -WhatIf` previews cleanly; `Test-DefenderDcPolicyXml` passes on generated files including MpCmdRun engine validation.
- [ ] CI (Pester 5.1 + 7.x, super-linter) green on the PR.
