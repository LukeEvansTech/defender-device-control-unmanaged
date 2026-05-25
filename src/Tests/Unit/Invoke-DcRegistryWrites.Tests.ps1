BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    Import-Module (Join-Path $ModuleRoot 'DefenderDeviceControlUnmanaged.psd1') -Force
}

Describe 'Invoke-DcRegistryWrites (registry mutator + rollback)' {
    BeforeAll {
        $script:manifest = @(
            [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control';                    Name = 'DefaultEnforcement';          Type = 'DWord';  Value = 1 }
            [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control';                    Name = 'SecuredDevicesConfiguration'; Type = 'String'; Value = 'RemovableMediaDevices|CdRomDevices|WpdDevices' }
            [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control\Policy Groups';      Name = 'PolicyGroups';                Type = 'String'; Value = 'C:\tmp\g.xml' }
            [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control\Policy Rules';       Name = 'PolicyRules';                 Type = 'String'; Value = 'C:\tmp\r.xml' }
            [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Features';                          Name = 'DeviceControlEnabled';        Type = 'DWord';  Value = 1 }
        )
    }

    Context 'happy path' {
        It 'invokes New-ItemProperty exactly once per manifest entry in order' {
            InModuleScope DefenderDeviceControlUnmanaged -Parameters @{ manifest = $script:manifest } {
                param($manifest)
                Mock Test-Path { $true }
                Mock New-Item { }
                Mock New-ItemProperty { }
                Mock Remove-DcPolicy { }

                Invoke-DcRegistryWrites -Manifest $manifest -Confirm:$false

                Should -Invoke New-ItemProperty -Times 5 -Exactly
                # Last write must be DeviceControlEnabled per the Catesta-style invariant
                Should -Invoke New-ItemProperty -ParameterFilter {
                    $Name -eq 'DeviceControlEnabled' -and $PropertyType -eq 'DWord' -and $Value -eq 1
                } -Times 1 -Exactly
                Should -Invoke Remove-DcPolicy -Times 0 -Exactly
            }
        }

        It 'creates missing parent keys before writing values' {
            InModuleScope DefenderDeviceControlUnmanaged -Parameters @{ manifest = $script:manifest } {
                param($manifest)
                Mock Test-Path { $false }
                Mock New-Item { }
                Mock New-ItemProperty { }
                Mock Remove-DcPolicy { }

                Invoke-DcRegistryWrites -Manifest $manifest -Confirm:$false

                Should -Invoke New-Item -Times 4 -Exactly
            }
        }
    }

    Context 'rollback when a mid-manifest write fails' {
        It 'calls Remove-DcPolicy and rethrows' {
            InModuleScope DefenderDeviceControlUnmanaged -Parameters @{ manifest = $script:manifest } {
                param($manifest)
                Mock Test-Path { $true }
                Mock New-Item { }
                $script:writeCount = 0
                Mock New-ItemProperty {
                    $script:writeCount++
                    if ($script:writeCount -eq 3) { throw 'simulated registry write failure' }
                }
                Mock Remove-DcPolicy { }

                { Invoke-DcRegistryWrites -Manifest $manifest -Confirm:$false } | Should -Throw -ExpectedMessage '*simulated registry write failure*'

                Should -Invoke Remove-DcPolicy -Times 1 -Exactly
                # First two writes succeeded; third threw; fourth+ never ran
                Should -Invoke New-ItemProperty -Times 3 -Exactly
            }
        }
    }

    Context 'WhatIf semantics' {
        It 'does not invoke New-Item or New-ItemProperty' {
            InModuleScope DefenderDeviceControlUnmanaged -Parameters @{ manifest = $script:manifest } {
                param($manifest)
                Mock Test-Path { $false }
                Mock New-Item { }
                Mock New-ItemProperty { }

                Invoke-DcRegistryWrites -Manifest $manifest -WhatIf

                Should -Invoke New-Item        -Times 0 -Exactly
                Should -Invoke New-ItemProperty -Times 0 -Exactly
            }
        }
    }
}
