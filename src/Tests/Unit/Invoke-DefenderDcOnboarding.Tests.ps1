BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force
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
            Mock Test-IsElevated { $false }
            { Invoke-DefenderDcOnboarding } | Should -Throw -ExpectedMessage '*elevated*'
        }
    }
}
