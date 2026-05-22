BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    Import-Module (Join-Path $ModuleRoot 'DefenderDeviceControlUnmanaged.psd1') -Force
}

Describe 'Get-DcMpCmdRunPath (MpCmdRun.exe discovery)' {
    Context 'when registry InstallLocation points at a real MpCmdRun.exe' {
        It 'returns the registry path' {
            InModuleScope DefenderDeviceControlUnmanaged {
                # Unix-style fake path keeps Join-Path happy when the test runs on macOS/Linux CI.
                Mock Get-ItemProperty {
                    [pscustomobject]@{ InstallLocation = '/fake/WindowsDefender/' }
                } -ParameterFilter { $Path -eq 'HKLM:\SOFTWARE\Microsoft\Windows Defender' }
                Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*MpCmdRun.exe' }
                Mock Get-ChildItem { } # should not be reached

                $result = Get-DcMpCmdRunPath

                $result | Should -BeLike '*MpCmdRun.exe'
                Should -Invoke Get-ChildItem -Times 0 -Exactly
            }
        }
    }

    Context 'when registry InstallLocation is set but MpCmdRun.exe is missing on disk' {
        It 'falls back to the newest Platform install' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Get-ItemProperty {
                    [pscustomobject]@{ InstallLocation = '/fake/WindowsDefender/' }
                }
                Mock Test-Path { $false }
                Mock Get-ChildItem {
                    @(
                        [pscustomobject]@{ FullName = '/fake/Platform/4.18.99/MpCmdRun.exe';  LastWriteTime = (Get-Date).AddDays(-1) }
                        [pscustomobject]@{ FullName = '/fake/Platform/4.18.100/MpCmdRun.exe'; LastWriteTime = (Get-Date) }
                    )
                }

                $result = Get-DcMpCmdRunPath

                $result | Should -Be '/fake/Platform/4.18.100/MpCmdRun.exe'
            }
        }
    }

    Context 'when registry InstallLocation is absent and Platform fallback also empty' {
        It 'returns $null' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Get-ItemProperty { $null }
                Mock Test-Path { $false }
                Mock Get-ChildItem { $null }

                $result = Get-DcMpCmdRunPath

                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'when neither InstallLocation registry value nor Platform path exists' {
        It 'returns $null without throwing' {
            InModuleScope DefenderDeviceControlUnmanaged {
                Mock Get-ItemProperty { $null }
                Mock Test-Path { $false }
                Mock Get-ChildItem { @() }

                { Get-DcMpCmdRunPath } | Should -Not -Throw
                Get-DcMpCmdRunPath | Should -BeNullOrEmpty
            }
        }
    }
}
