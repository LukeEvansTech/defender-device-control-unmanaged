BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    Import-Module (Join-Path $ModuleRoot 'DefenderDeviceControlUnmanaged.psd1') -Force
}

Describe 'Remove-DcPolicy (private; off-mode + rollback path)' {
    Context 'when neither DcRoot nor DcFeatures exist' {
        It 'does not call Remove-Item or Remove-ItemProperty' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-Path { $false }
                Mock Remove-Item { }
                Mock Remove-ItemProperty { }

                Remove-DcPolicy -Confirm:$false

                Should -Invoke Remove-Item        -Times 0 -Exactly
                Should -Invoke Remove-ItemProperty -Times 0 -Exactly
            }
        }
    }

    Context 'when only DcRoot exists' {
        It 'removes DcRoot recursively and leaves DcFeatures alone' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-Path { $true }  -ParameterFilter { $LiteralPath -eq $script:DcRoot }
                Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq $script:DcFeatures }
                Mock Remove-Item { }
                Mock Remove-ItemProperty { }
                Mock Get-ItemProperty { $null }

                Remove-DcPolicy -Confirm:$false

                Should -Invoke Remove-Item -ParameterFilter {
                    $LiteralPath -eq $script:DcRoot -and $Recurse
                } -Times 1 -Exactly
                Should -Invoke Remove-ItemProperty -Times 0 -Exactly
            }
        }
    }

    Context 'when DcFeatures exists with DeviceControlEnabled present' {
        It 'removes the DeviceControlEnabled property' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq $script:DcRoot }
                Mock Test-Path { $true }  -ParameterFilter { $LiteralPath -eq $script:DcFeatures }
                Mock Get-ItemProperty { [pscustomobject]@{ DeviceControlEnabled = 1 } } -ParameterFilter {
                    $LiteralPath -eq $script:DcFeatures -and $Name -eq 'DeviceControlEnabled'
                }
                Mock Remove-Item { }
                Mock Remove-ItemProperty { }

                Remove-DcPolicy -Confirm:$false

                Should -Invoke Remove-Item -Times 0 -Exactly
                Should -Invoke Remove-ItemProperty -ParameterFilter {
                    $LiteralPath -eq $script:DcFeatures -and $Name -eq 'DeviceControlEnabled'
                } -Times 1 -Exactly
            }
        }
    }

    Context 'when DcFeatures exists but DeviceControlEnabled is absent' {
        It 'does not remove the missing property' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq $script:DcRoot }
                Mock Test-Path { $true }  -ParameterFilter { $LiteralPath -eq $script:DcFeatures }
                Mock Get-ItemProperty { $null }
                Mock Remove-Item { }
                Mock Remove-ItemProperty { }

                Remove-DcPolicy -Confirm:$false

                Should -Invoke Remove-ItemProperty -Times 0 -Exactly
            }
        }
    }

    Context 'WhatIf semantics' {
        It 'does not mutate anything under -WhatIf' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-Path { $true }
                Mock Get-ItemProperty { [pscustomobject]@{ DeviceControlEnabled = 1 } }
                Mock Remove-Item { }
                Mock Remove-ItemProperty { }

                Remove-DcPolicy -WhatIf

                Should -Invoke Remove-Item        -Times 0 -Exactly
                Should -Invoke Remove-ItemProperty -Times 0 -Exactly
            }
        }
    }
}
