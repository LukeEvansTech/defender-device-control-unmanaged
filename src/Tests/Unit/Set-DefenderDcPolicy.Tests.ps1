BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force
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
}
