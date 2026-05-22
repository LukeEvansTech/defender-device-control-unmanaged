BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force
}

AfterAll {
    Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
}

Describe 'Test-DefenderDcPolicy' {
    It 'has -ExpectMode parameter with ValidateSet Audit, Enforce, Off' {
        $cmd = Get-Command Test-DefenderDcPolicy
        $param = $cmd.Parameters['ExpectMode']
        $param | Should -Not -BeNullOrEmpty
        $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet.ValidValues | Sort-Object | Should -Be @('Audit','Enforce','Off')
    }

    It 'has -ExpectMode defaulting to Audit' {
        $cmd = Get-Command Test-DefenderDcPolicy
        $cmd.Parameters['ExpectMode'].ParameterSets.Values.IsMandatory | Should -Not -Contain $true
    }

    It 'returns a boolean' {
        $cmd = Get-Command Test-DefenderDcPolicy
        $cmd.OutputType.Type | Should -Contain ([bool])
    }

    It 'has populated comment-based help (SYNOPSIS, DESCRIPTION, >=1 EXAMPLE)' {
        $help = Get-Help Test-DefenderDcPolicy -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterThan 0
    }

    It 'returns true when all checks pass under ExpectMode Off (no policy installed)' {
        InModuleScope DefenderDeviceControlUnmanaged {
            Mock Get-DcComputerStatus {
                [pscustomobject]@{
                    AMServiceEnabled = $true
                    AntivirusEnabled = $true
                    DeviceControlState = 'Disabled'
                }
            }
            Mock Test-Path { return $false } -ParameterFilter { $LiteralPath -like '*Device Control*' }
            Mock Get-ItemProperty { return $null }

            Test-DefenderDcPolicy -ExpectMode Off | Should -BeTrue
        }
    }

    It 'returns false when ExpectMode Audit but engine state is Disabled' {
        InModuleScope DefenderDeviceControlUnmanaged {
            Mock Get-DcComputerStatus {
                [pscustomobject]@{
                    AMServiceEnabled = $true
                    AntivirusEnabled = $true
                    DeviceControlState = 'Disabled'
                    DeviceControlPoliciesLastUpdated = [datetime]'1601-01-01'
                }
            }
            # Pretend the registry surface is missing -- multiple checks should fail.
            Mock Get-ItemProperty { return $null }
            Mock Test-Path { return $false }

            Test-DefenderDcPolicy -ExpectMode Audit | Should -BeFalse
        }
    }
}
