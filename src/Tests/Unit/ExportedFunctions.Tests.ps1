BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force
}

AfterAll {
    Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
}

Describe 'Exported functions surface' {
    It 'exports exactly 8 cmdlets' {
        $cmds = Get-Command -Module DefenderDeviceControlUnmanaged
        $cmds.Count | Should -Be 8
    }

    It 'exports the canonical 8 cmdlet names' {
        $expected = @(
            'Get-DefenderDcDevice',
            'Get-DefenderDcPolicy',
            'Invoke-DefenderDcOnboarding',
            'Invoke-DefenderDcUsbTest',
            'New-DefenderDcPolicy',
            'Set-DefenderDcPolicy',
            'Test-DefenderDcPolicy',
            'Test-DefenderDcPolicyXml'
        )
        $actual = (Get-Command -Module DefenderDeviceControlUnmanaged).Name | Sort-Object
        $actual | Should -Be ($expected | Sort-Object)
    }

    It 'does not leak private helpers' {
        $cmds = Get-Command -Module DefenderDeviceControlUnmanaged
        $cmds.Name | Should -Not -Contain 'Get-DcRegistryManifest'
        $cmds.Name | Should -Not -Contain 'Read-DcPolicyXml'
        $cmds.Name | Should -Not -Contain 'Remove-DcPolicy'
        $cmds.Name | Should -Not -Contain 'Invoke-DcRegistryWrites'
        $cmds.Name | Should -Not -Contain 'Test-DcXmlWithMpCmdRun'
        $cmds.Name | Should -Not -Contain 'Get-DcMpCmdRunPath'
        $cmds.Name | Should -Not -Contain 'Test-DcIsElevated'
        $cmds.Name | Should -Not -Contain 'Get-DcComputerStatus'
        $cmds.Name | Should -Not -Contain 'New-DcDeterministicGuid'
        $cmds.Name | Should -Not -Contain 'ConvertTo-DcPolicyXml'
        $cmds.Name | Should -Not -Contain 'ConvertTo-DcDevice'
        $cmds.Name | Should -Not -Contain 'Get-DcPnpEntity'
        $cmds.Name | Should -Not -Contain 'Add-DcDeviceRecord'
        $cmds.Name | Should -Not -Contain 'Test-DcIsWindows'
    }

    It 'every exported cmdlet has comment-based help with SYNOPSIS and EXAMPLES' {
        foreach ($name in (Get-Command -Module DefenderDeviceControlUnmanaged).Name) {
            $help = Get-Help $name -Full
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$name needs a SYNOPSIS"
            $help.examples.example.Count | Should -BeGreaterThan 0 -Because "$name needs at least one EXAMPLE"
        }
    }
}
