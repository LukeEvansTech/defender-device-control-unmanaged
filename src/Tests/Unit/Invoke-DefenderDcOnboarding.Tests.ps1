BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force

    # Get-Service / Stop-Transcript ship with PowerShell on Windows but not always on macOS;
    # stub them so InModuleScope tests can Mock them on cross-platform CI.
    InModuleScope DefenderDeviceControlUnmanaged {
        if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
            function global:Get-Service { param($Name, [switch]$ErrorAction) }
        }
    }
}

AfterAll {
    Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-DefenderDcOnboarding signature' {
    It 'has -OnboardingScript optional string parameter' {
        $cmd = Get-Command Invoke-DefenderDcOnboarding
        $param = $cmd.Parameters['OnboardingScript']
        $param | Should -Not -BeNullOrEmpty
        $param.ParameterType | Should -Be ([string])
        $isMandatory = $param.ParameterSets.Values.IsMandatory -contains $true
        $isMandatory | Should -BeFalse
    }

    It 'has -PostFlightWaitSeconds int parameter (with -SkipPostFlightWait alias)' {
        $cmd = Get-Command Invoke-DefenderDcOnboarding
        $param = $cmd.Parameters['PostFlightWaitSeconds']
        $param | Should -Not -BeNullOrEmpty
        $param.ParameterType | Should -Be ([int])
        $param.Aliases | Should -Contain 'SkipPostFlightWait'
    }

    It 'has populated comment-based help (SYNOPSIS, DESCRIPTION, >=1 EXAMPLE)' {
        $help = Get-Help Invoke-DefenderDcOnboarding -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterThan 0
    }

    It 'throws when invoked non-elevated' {
        InModuleScope DefenderDeviceControlUnmanaged {
            Mock Test-DcIsElevated { $false }
            { Invoke-DefenderDcOnboarding } | Should -Throw -ExpectedMessage '*elevated*'
        }
    }

    It 'declares SupportsShouldProcess so -WhatIf is supported' {
        $cmd = Get-Command Invoke-DefenderDcOnboarding
        $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue
    }
}

Describe 'Invoke-DefenderDcOnboarding pre-flight' {
    Context 'when the box is already onboarded (Sense Running + OnboardingState 1)' {
        It 'throws before invoking the onboarding script' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Test-DcIsElevated { $true }
                Mock Start-DcTranscript { '/tmp/fake.transcript.txt' }
                Mock Stop-Transcript { }
                Mock Get-DcComputerStatus {
                    [pscustomobject]@{ AMServiceEnabled = $true; AMEngineVersion = '0.0'; AMProductVersion = '0.0'; IsTamperProtected = $false }
                }
                Mock Get-Service {
                    [pscustomobject]@{ Name = 'Sense'; Status = 'Running' }
                } -ParameterFilter { $Name -eq 'Sense' }
                Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Windows Advanced Threat Protection\Status' }
                Mock Get-ItemProperty {
                    [pscustomobject]@{ OnboardingState = 1 }
                } -ParameterFilter { $Name -eq 'OnboardingState' }

                { Invoke-DefenderDcOnboarding } | Should -Throw -ExpectedMessage '*already onboarded*'
            }
        }
    }
}
