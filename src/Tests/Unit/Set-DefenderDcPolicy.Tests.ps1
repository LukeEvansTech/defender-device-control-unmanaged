BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force

    # Update-MpSignature ships with ConfigDefender on Windows; stub it inside the
    # module session-state so InModuleScope tests on macOS/Linux CI have something to mock.
    InModuleScope DefenderDeviceControlUnmanaged {
        if (-not (Get-Command Update-MpSignature -ErrorAction SilentlyContinue)) {
            function global:Update-MpSignature { param($UpdateSource) }
        }
    }
}

AfterAll {
    Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
}

Describe 'Set-DefenderDcPolicy' {
    It 'has -Mode parameter with ValidateSet Audit, Enforce, Off' {
        $cmd = Get-Command Set-DefenderDcPolicy
        $modeParam = $cmd.Parameters['Mode']
        $modeParam | Should -Not -BeNullOrEmpty
        $validateSet = $modeParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet.ValidValues | Sort-Object | Should -Be @('Audit','Enforce','Off')
    }

    It 'has -WhatIf support' {
        $cmd = Get-Command Set-DefenderDcPolicy
        $cmd.CmdletBinding | Should -BeTrue
        $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue
    }

    It 'accepts -GroupsXmlPath and -RulesXmlPath parameters' {
        $cmd = Get-Command Set-DefenderDcPolicy
        $cmd.Parameters.ContainsKey('GroupsXmlPath') | Should -BeTrue
        $cmd.Parameters.ContainsKey('RulesXmlPath') | Should -BeTrue
    }

    It 'accepts SkipMpCmdRunValidation + SkipGpUpdate switches' {
        $cmd = Get-Command Set-DefenderDcPolicy
        $cmd.Parameters.ContainsKey('SkipMpCmdRunValidation') | Should -BeTrue
        $cmd.Parameters.ContainsKey('SkipGpUpdate') | Should -BeTrue
    }

    It 'throws when invoked non-elevated (mocked Test-IsElevated returns false)' {
        InModuleScope DefenderDeviceControlUnmanaged {
            Mock Test-IsElevated { $false }
            { Set-DefenderDcPolicy -Mode Audit -WhatIf } | Should -Throw -ExpectedMessage '*elevated*'
        }
    }

    It 'has populated comment-based help (SYNOPSIS, DESCRIPTION, >=1 EXAMPLE)' {
        $help = Get-Help Set-DefenderDcPolicy -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterThan 0
    }

    Context 'Mode=Off branch (under elevation, mocked)' {
        It 'calls Remove-DcPolicy and skips XML/manifest pipeline' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-IsElevated { $true }
                Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true; AMEngineVersion = '0.0'; IsTamperProtected = $false } }
                Mock Remove-DcPolicy { }
                Mock Start-DcTranscript { '/tmp/fake.transcript.txt' }
                Mock Stop-Transcript { }
                Mock Get-DcRegistryManifest { }
                Mock Invoke-DcRegistryWrites { }
                Mock Read-DcPolicyXml { }
                Mock Test-DcXmlWithMpCmdRun { }
                Mock Update-MpSignature { }

                Set-DefenderDcPolicy -Mode Off -SkipGpUpdate -Confirm:$false

                Should -Invoke Remove-DcPolicy        -Times 1 -Exactly
                Should -Invoke Get-DcRegistryManifest -Times 0 -Exactly
                Should -Invoke Invoke-DcRegistryWrites -Times 0 -Exactly
                Should -Invoke Test-DcXmlWithMpCmdRun -Times 0 -Exactly
            }
        }
    }

    Context 'Apply branch with custom XML paths (under elevation, mocked)' {
        It 'validates + writes the manifest in order' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-IsElevated { $true }
                Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true; AMEngineVersion = '0.0'; IsTamperProtected = $false } }
                Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*.xml' }
                Mock Test-DefenderDcPolicyXml { $true }
                Mock Read-DcPolicyXml { @() }
                Mock Get-DcRegistryManifest {
                    @([pscustomobject]@{ Path='x'; Name='n'; Type='DWord'; Value=1 })
                }
                Mock Remove-DcPolicy { }
                Mock Invoke-DcRegistryWrites { }
                Mock Start-DcTranscript { '/tmp/fake.transcript.txt' }
                Mock Stop-Transcript { }
                Mock Update-MpSignature { }

                Set-DefenderDcPolicy -Mode Audit -GroupsXmlPath '/tmp/g.xml' -RulesXmlPath '/tmp/r.xml' -SkipGpUpdate -Confirm:$false

                # Pre-apply cleanup, then manifest write
                Should -Invoke Remove-DcPolicy            -Times 1 -Exactly
                Should -Invoke Test-DefenderDcPolicyXml   -Times 2 -Exactly
                Should -Invoke Get-DcRegistryManifest     -Times 1 -Exactly
                Should -Invoke Invoke-DcRegistryWrites    -Times 1 -Exactly
            }
        }

        It '-SkipMpCmdRunValidation falls back to a parse-only Read-DcPolicyXml check' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-IsElevated { $true }
                Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true; AMEngineVersion = '0.0'; IsTamperProtected = $false } }
                Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*.xml' }
                Mock Test-DefenderDcPolicyXml { $true }
                Mock Read-DcPolicyXml { @() }
                Mock Get-DcRegistryManifest { @([pscustomobject]@{ Path='x'; Name='n'; Type='DWord'; Value=1 }) }
                Mock Remove-DcPolicy { }
                Mock Invoke-DcRegistryWrites { }
                Mock Start-DcTranscript { '/tmp/fake.transcript.txt' }
                Mock Stop-Transcript { }
                Mock Update-MpSignature { }

                Set-DefenderDcPolicy -Mode Enforce -GroupsXmlPath '/tmp/g.xml' -RulesXmlPath '/tmp/r.xml' -SkipMpCmdRunValidation -SkipGpUpdate -Confirm:$false

                Should -Invoke Test-DefenderDcPolicyXml   -Times 0 -Exactly
                Should -Invoke Read-DcPolicyXml           -Times 2 -Exactly
                Should -Invoke Invoke-DcRegistryWrites    -Times 1 -Exactly
            }
        }

        It 'throws when Test-DefenderDcPolicyXml returns false' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-IsElevated { $true }
                Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true; AMEngineVersion = '0.0'; IsTamperProtected = $false } }
                Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*.xml' }
                Mock Test-DefenderDcPolicyXml { $false }
                Mock Read-DcPolicyXml { @() }
                Mock Get-DcRegistryManifest { @() }
                Mock Remove-DcPolicy { }
                Mock Invoke-DcRegistryWrites { }
                Mock Start-DcTranscript { '/tmp/fake.transcript.txt' }
                Mock Stop-Transcript { }
                Mock Update-MpSignature { }

                { Set-DefenderDcPolicy -Mode Audit -GroupsXmlPath '/tmp/g.xml' -RulesXmlPath '/tmp/r.xml' -SkipGpUpdate -Confirm:$false } |
                    Should -Throw -ExpectedMessage '*failed validation*'

                Should -Invoke Invoke-DcRegistryWrites -Times 0 -Exactly
            }
        }

        It 'throws when Defender AM service is not enabled' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-IsElevated { $true }
                Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $false } }
                Mock Start-DcTranscript { '/tmp/fake.transcript.txt' }
                Mock Stop-Transcript { }

                { Set-DefenderDcPolicy -Mode Audit -SkipGpUpdate -Confirm:$false } |
                    Should -Throw -ExpectedMessage '*Defender service not enabled*'
            }
        }
    }
}
