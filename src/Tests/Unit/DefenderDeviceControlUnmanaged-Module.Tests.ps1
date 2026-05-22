BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
}

Describe 'Module manifest' {
    It 'passes Test-ModuleManifest' {
        $m = Test-ModuleManifest -Path $script:ModuleManifest
        $m | Should -Not -BeNullOrEmpty
    }

    It 'has ModuleVersion 1.0.0' {
        $m = Test-ModuleManifest -Path $script:ModuleManifest
        $m.Version.ToString() | Should -Be '1.0.0'
    }

    It 'declares CompatiblePSEditions Core and Desktop' {
        $raw = Import-PowerShellDataFile -Path $script:ModuleManifest
        $raw.CompatiblePSEditions | Should -Contain 'Core'
        $raw.CompatiblePSEditions | Should -Contain 'Desktop'
    }

    It 'declares PowerShellVersion >= 5.1' {
        $raw = Import-PowerShellDataFile -Path $script:ModuleManifest
        [version]$raw.PowerShellVersion -ge [version]'5.1' | Should -BeTrue
    }

    It 'declares the required tags' {
        $raw = Import-PowerShellDataFile -Path $script:ModuleManifest
        $tags = $raw.PrivateData.PSData.Tags
        foreach ($t in 'Defender','DeviceControl','USB','MDE','Security') {
            $tags | Should -Contain $t
        }
    }
}
