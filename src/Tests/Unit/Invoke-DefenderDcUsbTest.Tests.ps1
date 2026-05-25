BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force

    InModuleScope DefenderDeviceControlUnmanaged {
        if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
            function global:Get-Service { param($Name, [switch]$ErrorAction) }
        }
        if (-not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) {
            function global:Get-WinEvent { param($LogName, $MaxEvents, [switch]$ErrorAction) }
        }
    }
}

AfterAll {
    Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-DefenderDcUsbTest signature' {
    It 'has -Drive parameter (mandatory)' {
        $cmd = Get-Command Invoke-DefenderDcUsbTest
        $param = $cmd.Parameters['Drive']
        $param | Should -Not -BeNullOrEmpty
        $isMandatory = $param.ParameterSets.Values.IsMandatory -contains $true
        $isMandatory | Should -BeTrue
    }

    It 'has -StartMode parameter with ValidateSet Audit, Enforce' {
        $cmd = Get-Command Invoke-DefenderDcUsbTest
        $param = $cmd.Parameters['StartMode']
        $param | Should -Not -BeNullOrEmpty
        $vs = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Sort-Object | Should -Be @('Audit','Enforce')
    }

    It 'has -KeepDcApplied switch' {
        $cmd = Get-Command Invoke-DefenderDcUsbTest
        $cmd.Parameters.ContainsKey('KeepDcApplied') | Should -BeTrue
        $cmd.Parameters['KeepDcApplied'].SwitchParameter | Should -BeTrue
    }

    It 'has populated comment-based help (SYNOPSIS, DESCRIPTION, >=1 EXAMPLE)' {
        $help = Get-Help Invoke-DefenderDcUsbTest -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterThan 0
    }

    It 'throws when invoked non-elevated' {
        InModuleScope DefenderDeviceControlUnmanaged {
            Mock Test-DcIsElevated { $false }
            { Invoke-DefenderDcUsbTest -Drive E } | Should -Throw -ExpectedMessage '*elevated*'
        }
    }

    Describe 'Invoke-DefenderDcUsbTest execution' {
        It 'skips policy apply, manual interaction, and rollback under -WhatIf' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-DcIsElevated { $true }
                Mock Start-DcTranscript { '/tmp/fake.transcript.txt' }
                Mock Stop-Transcript { }
                Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true } }
                Mock Get-Service { [pscustomobject]@{ Name = 'Sense'; Status = 'Running' } } -ParameterFilter { $Name -eq 'Sense' }
                Mock Get-DefenderDcPolicy { [pscustomobject]@{ Mode = 'Off' } }
                Mock Set-DefenderDcPolicy { }
                Mock Test-DefenderDcPolicy { $true }
                Mock Read-Host { }
                Mock Get-WinEvent { @() }

                $result = Invoke-DefenderDcUsbTest -Drive E -WhatIf

                $result.PreTestMode | Should -Be 'Off'
                Should -Invoke Set-DefenderDcPolicy  -Times 0 -Exactly
                Should -Invoke Test-DefenderDcPolicy -Times 0 -Exactly
                Should -Invoke Read-Host             -Times 0 -Exactly
                Should -Invoke Get-WinEvent          -Times 0 -Exactly
            }
        }

        Context 'Regression: -WhatIf with unmocked Start/Stop-Transcript (Windows-only)' {
            # See Set-DefenderDcPolicy.Tests.ps1 for the full rationale. The
            # Start-Transcript / Stop-Transcript pair under -WhatIf raised
            # "host is not currently transcribing" from the finally block.
            It '-WhatIf completes without throwing when transcript helpers are not mocked' -Skip:($env:OS -ne 'Windows_NT') {
                InModuleScope DefenderDeviceControlUnmanaged {
                    Mock Test-DcIsElevated { $true }
                    Mock Get-DcComputerStatus { [pscustomobject]@{ AMServiceEnabled = $true } }
                    Mock Get-Service { [pscustomobject]@{ Name = 'Sense'; Status = 'Running' } } -ParameterFilter { $Name -eq 'Sense' }
                    Mock Get-DefenderDcPolicy { [pscustomobject]@{ Mode = 'Off' } }
                    Mock Set-DefenderDcPolicy { }
                    Mock Test-DefenderDcPolicy { $true }
                    Mock Read-Host { }
                    Mock Get-WinEvent { @() }
                    # Deliberately NOT mocking Start-DcTranscript / Stop-Transcript.

                    { Invoke-DefenderDcUsbTest -Drive E -WhatIf } | Should -Not -Throw
                }
            }
        }
    }
}
