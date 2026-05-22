BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
}

Describe 'Module import end-to-end' {
    It 'imports without errors' {
        { Import-Module $script:ModuleManifest -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'all 6 cmdlets are callable (signature only, no side effects)' {
        Import-Module $script:ModuleManifest -Force
        try {
            foreach ($name in @('Get-DefenderDcPolicy','Invoke-DefenderDcOnboarding','Invoke-DefenderDcUsbTest','Set-DefenderDcPolicy','Test-DefenderDcPolicy','Test-DefenderDcPolicyXml')) {
                (Get-Command $name) | Should -Not -BeNullOrEmpty
            }
        } finally {
            Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
        }
    }
}
