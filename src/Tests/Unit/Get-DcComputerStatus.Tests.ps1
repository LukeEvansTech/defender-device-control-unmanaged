# Regression coverage for the Private/Get-DcComputerStatus.ps1 wrapper.
#
# Every other test in the suite Mocks Get-DcComputerStatus to avoid touching
# the real Defender module - that is the whole reason the wrapper exists. As
# a consequence, the wrapper body itself (which does the live Get-Command
# resolution of Get-MpComputerStatus) is never exercised by the cross-platform
# suite. A regression that ships in that one line will go undetected on every
# CI job that mocks the wrapper, which is all of them.
#
# These tests fill that gap by calling the wrapper unmocked on a real
# Defender-attached Windows host. Skipped on macOS / Linux and on Windows
# hosts without the in-box Defender module.

# Skip predicate must be evaluated at Pester discovery time, so it lives at
# script scope rather than inside BeforeAll.
$script:CanTestDefenderWrapper = (
    $env:OS -eq 'Windows_NT' -and
    $null -ne (Get-Module -Name Defender -ListAvailable -ErrorAction SilentlyContinue)
)

BeforeAll {
    $ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force

    if ($script:CanTestDefenderWrapper) {
        Import-Module Defender -Force -ErrorAction Stop
    }
}

AfterAll {
    Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
}

Describe 'Get-DcComputerStatus (real Defender, Windows-only)' {
    It 'resolves Get-MpComputerStatus through Get-Command without throwing' -Skip:(-not $script:CanTestDefenderWrapper) {
        # Regression: the wrapper previously filtered Get-Command with
        # -CommandType Cmdlet. Get-MpComputerStatus is a CDXML-backed Function
        # in the in-box Defender module, so the filter raised
        # CommandNotFoundException on every real Windows box - which killed
        # Test-DefenderDcPolicy as soon as it reached the engine-state checks.
        InModuleScope DefenderDeviceControlUnmanaged {
            { Get-DcComputerStatus } | Should -Not -Throw
        }
    }

    It 'returns an object exposing the AMServiceEnabled property the rest of the module reads' -Skip:(-not $script:CanTestDefenderWrapper) {
        InModuleScope DefenderDeviceControlUnmanaged {
            $status = Get-DcComputerStatus
            $status | Should -Not -BeNullOrEmpty
            $status.PSObject.Properties['AMServiceEnabled'] | Should -Not -BeNullOrEmpty
        }
    }
}
