BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force
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
}
