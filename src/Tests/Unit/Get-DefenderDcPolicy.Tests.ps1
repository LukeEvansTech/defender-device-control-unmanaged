BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force
}

AfterAll {
    Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
}

Describe 'Get-DefenderDcPolicy' {
    It 'has no required parameters' {
        $cmd = Get-Command Get-DefenderDcPolicy
        $mandatoryParams = $cmd.Parameters.Values | Where-Object {
            $_.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }
        }
        $mandatoryParams.Count | Should -Be 0
    }

    It 'returns a [pscustomobject]' {
        $cmd = Get-Command Get-DefenderDcPolicy
        $cmd.OutputType.Type | Should -Contain ([pscustomobject])
    }

    It 'has populated comment-based help (SYNOPSIS, DESCRIPTION, >=1 EXAMPLE)' {
        $help = Get-Help Get-DefenderDcPolicy -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterThan 0
    }

    Context 'when no policy is installed (registry absent, engine reports Disabled)' {
        It "returns Mode='Off' and null XML paths" {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Get-DcComputerStatus {
                    [pscustomobject]@{ DeviceControlState = 'Disabled'; DeviceControlPoliciesLastUpdated = [datetime]'1601-01-01' }
                }
                Mock Get-ItemProperty { return $null }
                Mock Test-Path { return $false }

                $result = Get-DefenderDcPolicy
                $result.Mode | Should -Be 'Off'
                $result.PolicyGroupsXmlPath | Should -BeNullOrEmpty
                $result.PolicyRulesXmlPath  | Should -BeNullOrEmpty
                $result.DeviceControlState | Should -Be 'Disabled'
            }
        }
    }

    Context 'when policy is in Audit mode (Rules XML contains AuditAllowed entries)' {
        It "returns Mode='Audit'" {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Get-DcComputerStatus {
                    [pscustomobject]@{ DeviceControlState = 'Enabled'; DeviceControlPoliciesLastUpdated = (Get-Date) }
                }
                # Compose a Get-ItemProperty mock that returns plausible values per Name
                Mock Get-ItemProperty {
                    param($LiteralPath, $Name)
                    switch ($Name) {
                        'DeviceControlEnabled' { return [pscustomobject]@{ DeviceControlEnabled = 1 } }
                        'DefaultEnforcement'   { return [pscustomobject]@{ DefaultEnforcement = 1 } }
                        'SecuredDevicesConfiguration' { return [pscustomobject]@{ SecuredDevicesConfiguration = 'RemovableMediaDevices|CdRomDevices|WpdDevices' } }
                        'PolicyGroups' { return [pscustomobject]@{ PolicyGroups = '/tmp/fake-Groups.xml' } }
                        'PolicyRules'  { return [pscustomobject]@{ PolicyRules  = '/tmp/fake-Rules.xml' } }
                        default { return $null }
                    }
                }
                Mock Test-Path { return $true } -ParameterFilter { $LiteralPath -like '*Rules.xml' }
                Mock Test-Path { return $false }
                Mock Read-DcPolicyXml {
                    # Return a single Rule with an AuditAllowed entry
                    $rawXml = '<PolicyRule Id="{x}"><Entry Id="{y}"><Type>AuditAllowed</Type></Entry></PolicyRule>'
                    [pscustomobject]@{ Kind='Rule'; Guid='{x}'; RawXml = $rawXml }
                }

                $result = Get-DefenderDcPolicy
                $result.Mode | Should -Be 'Audit'
                $result.FeaturesDeviceControlEnabled | Should -Be 1
                $result.DefaultEnforcement | Should -Be 1
                $result.SecuredDevicesConfiguration | Should -Be 'RemovableMediaDevices|CdRomDevices|WpdDevices'
            }
        }
    }

    Context 'when policy is in Enforce mode (Rules XML contains Deny entries)' {
        It "returns Mode='Enforce'" {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Get-DcComputerStatus {
                    [pscustomobject]@{ DeviceControlState = 'Enabled'; DeviceControlPoliciesLastUpdated = (Get-Date) }
                }
                Mock Get-ItemProperty {
                    param($LiteralPath, $Name)
                    switch ($Name) {
                        'PolicyRules'  { return [pscustomobject]@{ PolicyRules  = '/tmp/fake-Rules.xml' } }
                        default { return $null }
                    }
                }
                Mock Test-Path { return $true } -ParameterFilter { $LiteralPath -like '*Rules.xml' }
                Mock Test-Path { return $false }
                Mock Read-DcPolicyXml {
                    $rawXml = '<PolicyRule Id="{x}"><Entry Id="{y}"><Type>Deny</Type></Entry></PolicyRule>'
                    [pscustomobject]@{ Kind='Rule'; Guid='{x}'; RawXml = $rawXml }
                }

                $result = Get-DefenderDcPolicy
                $result.Mode | Should -Be 'Enforce'
            }
        }
    }
}
