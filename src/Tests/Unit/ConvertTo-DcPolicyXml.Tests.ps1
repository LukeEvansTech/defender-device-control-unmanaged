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
