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

        It 'accumulates multiple piped devices into the approved group' {
            $out = Join-Path $TestDrive 'multi'
            $devices = @(
                [pscustomobject]@{ InstancePathId = 'USBSTOR\DISK\SERA&0' },
                [pscustomobject]@{ InstancePathId = 'USBSTOR\DISK\SERB&0' }
            )
            $result = $devices | New-DefenderDcPolicy -Usb ReadOnly -OutputPath $out
            $groups = [xml](Get-Content -LiteralPath $result.GroupsXmlPath -Raw)
            $approved = @($groups.Groups.Group) | Where-Object { $_.Name -eq 'Approved devices' }
            @($approved.DescriptorIdList.InstancePathId).Count | Should -Be 2
        }

        It 'threads -PolicyName into generated group and rule names' {
            $out = Join-Path $TestDrive 'named'
            $result = New-DefenderDcPolicy -Usb ReadOnly -PolicyName 'Kiosk lockdown' -OutputPath $out
            (Get-Content -LiteralPath $result.GroupsXmlPath -Raw) | Should -Match 'Kiosk lockdown'
            (Get-Content -LiteralPath $result.EnforceRulesXmlPath -Raw) | Should -Match 'Kiosk lockdown'
        }
    }
}
