BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\ConvertTo-DcDevice.ps1')

    function script:New-FakePnp {
        param($Name, $PNPDeviceID, $PNPClass, $HardwareID)
        [pscustomobject]@{
            Name        = $Name
            PNPDeviceID = $PNPDeviceID
            PNPClass    = $PNPClass
            HardwareID  = $HardwareID
        }
    }
}

Describe 'ConvertTo-DcDevice' {
    It 'classifies USBSTOR instance ids as Usb and extracts the serial' {
        $d = ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Kingston DataTraveler 3.0 USB Device' `
            -PNPDeviceID 'USBSTOR\DISK&VEN_KINGSTON&PROD_DATATRAVELER_3.0&REV_PMAP\E0D55EA574DBF750E97B0A14&0' `
            -PNPClass 'DiskDrive' `
            -HardwareID @('USBSTOR\DiskKingstonDataTraveler_3.0'))
        $d.Class          | Should -Be 'Usb'
        $d.FriendlyName   | Should -Be 'Kingston DataTraveler 3.0 USB Device'
        $d.InstancePathId | Should -Be 'USBSTOR\DISK&VEN_KINGSTON&PROD_DATATRAVELER_3.0&REV_PMAP\E0D55EA574DBF750E97B0A14&0'
        $d.SerialNumber   | Should -Be 'E0D55EA574DBF750E97B0A14'
        $d.HardwareIds    | Should -Contain 'USBSTOR\DiskKingstonDataTraveler_3.0'
    }

    It 'classifies PNPClass CDROM as Optical' {
        (ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'DVD Drive' `
            -PNPDeviceID 'SCSI\CDROM&VEN_X\5&1&0' -PNPClass 'CDROM' -HardwareID @())).Class |
            Should -Be 'Optical'
    }

    It 'classifies PNPClass WPD as Wpd and extracts VID_PID' {
        $d = ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Pixel 8' `
            -PNPDeviceID 'USB\VID_18D1&PID_4EE1\SERIAL123' -PNPClass 'WPD' `
            -HardwareID @('USB\VID_18D1&PID_4EE1&REV_0440'))
        $d.Class  | Should -Be 'Wpd'
        $d.VidPid | Should -Be 'VID_18D1&PID_4EE1'
        $d.SerialNumber | Should -Be 'SERIAL123'
    }

    It 'returns nothing for untracked device classes' {
        ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Intel(R) GPU' `
            -PNPDeviceID 'PCI\VEN_8086&DEV_X\3&1' -PNPClass 'Display' -HardwareID @()) |
            Should -BeNullOrEmpty
    }

    It 'VidPid is null when no VID/PID pattern is present (USBSTOR child nodes)' {
        $d = ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Disk' `
            -PNPDeviceID 'USBSTOR\DISK&VEN_K&PROD_P&REV_1\SER&0' -PNPClass 'DiskDrive' -HardwareID @())
        $d.VidPid | Should -BeNullOrEmpty
    }

    It 'tolerates a missing PNPClass property (strict-mode safe)' {
        $entity = [pscustomobject]@{ Name = 'X'; PNPDeviceID = 'USBSTOR\DISK\S&0'; HardwareID = $null }
        { ConvertTo-DcDevice -PnpEntity $entity } | Should -Not -Throw
    }

    It 'stamps CapturedAt as an ISO-8601 UTC string and tags the type name' {
        $d = ConvertTo-DcDevice -PnpEntity (New-FakePnp -Name 'Disk' `
            -PNPDeviceID 'USBSTOR\DISK\SER&0' -PNPClass 'DiskDrive' -HardwareID @())
        $d.CapturedAt | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        $d.PSObject.TypeNames | Should -Contain 'DefenderDeviceControlUnmanaged.Device'
    }
}
