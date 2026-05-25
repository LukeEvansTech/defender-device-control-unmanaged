BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
}

Describe 'Module manifest' {
    It 'passes Test-ModuleManifest' {
        $m = Test-ModuleManifest -Path $script:ModuleManifest
        $m | Should -Not -BeNullOrEmpty
    }

    It 'declares a parseable ModuleVersion at or above 1.0.0' {
        # Version-agnostic on purpose - the publish workflow asserts the tag
        # matches the manifest version, so we only need to know that the field
        # is set and parses as a real [version], not what the literal value is.
        # Pinning a literal here meant every release commit shipped with a
        # red test for the unrelated assertion (see v1.0.1).
        $m = Test-ModuleManifest -Path $script:ModuleManifest
        $m.Version | Should -BeOfType ([version])
        $m.Version -ge [version]'1.0.0' | Should -BeTrue
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
