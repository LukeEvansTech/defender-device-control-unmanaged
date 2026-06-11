BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\ConvertTo-DcDevice.ps1')
    . (Join-Path $ModuleRoot 'Private\Get-DcPnpEntity.ps1')
    . (Join-Path $ModuleRoot 'Private\Add-DcDeviceRecord.ps1')
    . (Join-Path $ModuleRoot 'Private\Test-DcIsWindows.ps1')
    . (Join-Path $ModuleRoot 'Public\Get-DefenderDcDevice.ps1')

    $script:FakeUsb = [pscustomobject]@{
        Name        = 'Kingston DataTraveler 3.0 USB Device'
        PNPDeviceID = 'USBSTOR\DISK&VEN_KINGSTON&PROD_DT&REV_1\SER123&0'
        PNPClass    = 'DiskDrive'
        HardwareID  = @('USBSTOR\DiskKingstonDT')
    }
    $script:FakeGpu = [pscustomobject]@{
        Name        = 'Intel GPU'
        PNPDeviceID = 'PCI\VEN_8086&DEV_1\3&1'
        PNPClass    = 'Display'
        HardwareID  = @()
    }
}

Describe 'Get-DefenderDcDevice (snapshot)' {
    BeforeEach {
        # Dev box is macOS; the cmdlet's platform gate must be mocked away.
        Mock Test-DcIsWindows { $true }
    }

    It 'returns only tracked-class devices' {
        Mock Get-DcPnpEntity { @($FakeUsb, $FakeGpu) }
        $devices = @(Get-DefenderDcDevice)
        $devices.Count | Should -Be 1
        $devices[0].Class | Should -Be 'Usb'
        $devices[0].InstancePathId | Should -Be 'USBSTOR\DISK&VEN_KINGSTON&PROD_DT&REV_1\SER123&0'
    }

    It 'writes captured devices to -OutFile' {
        Mock Get-DcPnpEntity { @($FakeUsb) }
        $path = Join-Path $TestDrive 'snap.json'
        Get-DefenderDcDevice -OutFile $path | Out-Null
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count | Should -Be 1
    }

    It 'rejects -TimeoutSeconds without -Watch' {
        { Get-DefenderDcDevice -TimeoutSeconds 5 } |
            Should -Throw -ExpectedMessage '*-TimeoutSeconds requires -Watch*'
    }

    It 'has populated comment-based help (SYNOPSIS + EXAMPLE)' {
        $help = Get-Help Get-DefenderDcDevice -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-DefenderDcDevice (-Watch)' {
    BeforeEach {
        Mock Test-DcIsWindows { $true }
        Mock Register-CimIndicationEvent { }
        Mock Unregister-Event { }
        Mock Get-Event { @() }
        Mock Remove-Event { }
    }

    It 'emits a device per arrival event and stops at the timeout' {
        $script:waitCalls = 0
        Mock Wait-Event {
            $script:waitCalls++
            if ($script:waitCalls -eq 1) {
                [pscustomobject]@{
                    EventIdentifier = 11
                    SourceEventArgs = [pscustomobject]@{
                        NewEvent = [pscustomobject]@{ TargetInstance = $FakeUsb }
                    }
                }
            }
            # subsequent calls: $null (no event within the 1s poll)
        }

        $devices = @(Get-DefenderDcDevice -Watch -TimeoutSeconds 2)
        $devices.Count | Should -Be 1
        $devices[0].Class | Should -Be 'Usb'
        Should -Invoke Register-CimIndicationEvent -Times 1 -Exactly
        Should -Invoke Remove-Event -Times 1 -Exactly
    }

    It 'always unregisters the event subscription (finally)' {
        Mock Wait-Event { $null }
        Get-DefenderDcDevice -Watch -TimeoutSeconds 1 | Out-Null
        Should -Invoke Unregister-Event -Times 1 -Exactly
    }

    It 'appends watched devices to -OutFile' {
        $script:waitCalls2 = 0
        Mock Wait-Event {
            $script:waitCalls2++
            if ($script:waitCalls2 -eq 1) {
                [pscustomobject]@{
                    EventIdentifier = 12
                    SourceEventArgs = [pscustomobject]@{
                        NewEvent = [pscustomobject]@{ TargetInstance = $FakeUsb }
                    }
                }
            }
        }
        $path = Join-Path $TestDrive 'watch.json'
        Get-DefenderDcDevice -Watch -TimeoutSeconds 2 -OutFile $path | Out-Null
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count | Should -Be 1
    }

    It 'ignores arrival events for untracked device classes' {
        $script:waitCalls3 = 0
        Mock Wait-Event {
            $script:waitCalls3++
            if ($script:waitCalls3 -eq 1) {
                [pscustomobject]@{
                    EventIdentifier = 13
                    SourceEventArgs = [pscustomobject]@{
                        NewEvent = [pscustomobject]@{ TargetInstance = $FakeGpu }
                    }
                }
            }
        }
        @(Get-DefenderDcDevice -Watch -TimeoutSeconds 2).Count | Should -Be 0
    }
}
