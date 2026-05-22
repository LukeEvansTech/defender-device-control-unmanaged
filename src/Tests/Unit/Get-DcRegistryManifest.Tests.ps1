BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    # Constants live in Imports.ps1, dot-source that first
    . (Join-Path $ModuleRoot 'Imports.ps1')
    . (Join-Path $ModuleRoot 'Private\Get-DcRegistryManifest.ps1')
}

Describe 'Get-DcRegistryManifest (GPO file-path schema)' {
    It 'rejects relative paths for GroupsXmlPath' {
        { Get-DcRegistryManifest -GroupsXmlPath 'relative.xml' -RulesXmlPath 'C:\abs.xml' } |
            Should -Throw -ExpectedMessage '*absolute path*'
    }

    It 'rejects relative paths for RulesXmlPath' {
        { Get-DcRegistryManifest -GroupsXmlPath 'C:\abs.xml' -RulesXmlPath 'relative.xml' } |
            Should -Throw -ExpectedMessage '*absolute path*'
    }

    It 'produces exactly 5 writes' {
        $m = Get-DcRegistryManifest -GroupsXmlPath 'C:\tmp\g.xml' -RulesXmlPath 'C:\tmp\r.xml'
        @($m).Count | Should -Be 5
    }

    It 'writes Features\DeviceControlEnabled (DWORD=1) as the LAST write' {
        $m = Get-DcRegistryManifest -GroupsXmlPath 'C:\tmp\g.xml' -RulesXmlPath 'C:\tmp\r.xml'
        $m[-1].Path  | Should -BeLike '*\Features'
        $m[-1].Name  | Should -Be 'DeviceControlEnabled'
        $m[-1].Type  | Should -Be 'DWord'
        $m[-1].Value | Should -Be 1
    }

    It 'writes the groups XML path as REG_SZ named PolicyGroups under "Policy Groups" sub-key' {
        $m = Get-DcRegistryManifest -GroupsXmlPath 'C:\tmp\g.xml' -RulesXmlPath 'C:\tmp\r.xml'
        $gw = $m | Where-Object Name -EQ 'PolicyGroups'
        $gw.Path  | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control\Policy Groups'
        $gw.Type  | Should -Be 'String'
        $gw.Value | Should -Be 'C:\tmp\g.xml'
    }

    It 'writes the rules XML path as REG_SZ named PolicyRules under "Policy Rules" sub-key' {
        $m = Get-DcRegistryManifest -GroupsXmlPath 'C:\tmp\g.xml' -RulesXmlPath 'C:\tmp\r.xml'
        $rw = $m | Where-Object Name -EQ 'PolicyRules'
        $rw.Path  | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control\Policy Rules'
        $rw.Type  | Should -Be 'String'
        $rw.Value | Should -Be 'C:\tmp\r.xml'
    }

    It 'sets DefaultEnforcement to 1 (Allow) so non-rule devices stay usable' {
        $m = Get-DcRegistryManifest -GroupsXmlPath 'C:\tmp\g.xml' -RulesXmlPath 'C:\tmp\r.xml'
        $df = $m | Where-Object Name -EQ 'DefaultEnforcement'
        $df.Path  | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control'
        $df.Type  | Should -Be 'DWord'
        $df.Value | Should -Be 1
    }

    It 'sets SecuredDevicesConfiguration to the three secured classes (no PrinterDevices)' {
        $m = Get-DcRegistryManifest -GroupsXmlPath 'C:\tmp\g.xml' -RulesXmlPath 'C:\tmp\r.xml'
        $s = $m | Where-Object Name -EQ 'SecuredDevicesConfiguration'
        $s.Path  | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control'
        $s.Type  | Should -Be 'String'
        $s.Value | Should -Be 'RemovableMediaDevices|CdRomDevices|WpdDevices'
    }
}
