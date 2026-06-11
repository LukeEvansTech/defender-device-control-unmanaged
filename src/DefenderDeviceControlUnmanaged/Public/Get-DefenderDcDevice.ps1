function Get-DefenderDcDevice {
    <#
    .SYNOPSIS
        Capture the hardware identifiers of removable, WPD, and optical
        devices for Device Control policy crafting.

    .DESCRIPTION
        Snapshot mode (default) enumerates currently-connected devices in the
        classes this module tracks (USB removable storage, WPD/MTP, optical)
        and emits one record per device with its Device Control-usable
        descriptors: InstancePathId (serial-specific), HardwareIds
        (model-wide), VID/PID, serial, friendly name.

        -Watch subscribes to PnP device-arrival events: plug devices in one by
        one and each is emitted as it arrives, until Ctrl+C or
        -TimeoutSeconds. Read-only PnP queries; no elevation required.

        -OutFile appends each record to a JSON array file as it is captured
        (deduped by InstancePathId), which is exactly the
        New-DefenderDcPolicy -AllowDeviceFile input.

    .PARAMETER Watch
        Subscribe to device-arrival events and emit devices as they are
        plugged in, instead of a one-shot snapshot.

    .PARAMETER TimeoutSeconds
        Stop watching after this many seconds. Only valid with -Watch.
        Without it, -Watch runs until Ctrl+C.

    .PARAMETER OutFile
        JSON file to append captured devices to (created on first capture).

    .EXAMPLE
        Get-DefenderDcDevice

        List currently-connected removable/WPD/optical devices.

    .EXAMPLE
        Get-DefenderDcDevice -Watch -OutFile .\approved.json

        Plug approved sticks in one by one; each is printed and appended to
        approved.json. Ctrl+C when done.

    .EXAMPLE
        Get-DefenderDcDevice -Watch -TimeoutSeconds 60 |
            New-DefenderDcPolicy -Usb ReadOnly -OutputPath .\policy\

        Capture for one minute, then craft a policy exempting what arrived.

    .LINK
        https://lukeevanstech.github.io/defender-device-control-unmanaged/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch] $Watch,

        [Alias('Timeout')]
        [int] $TimeoutSeconds,

        [string] $OutFile
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($TimeoutSeconds -and -not $Watch) {
        throw 'Get-DefenderDcDevice: -TimeoutSeconds requires -Watch.'
    }

    if (-not (Test-DcIsWindows)) {
        throw 'Get-DefenderDcDevice: requires Windows (CIM/PnP device enumeration).'
    }

    if (-not $Watch) {
        foreach ($entity in @(Get-DcPnpEntity)) {
            $device = ConvertTo-DcDevice -PnpEntity $entity
            if ($null -eq $device) { continue }
            if ($OutFile) { Add-DcDeviceRecord -Path $OutFile -Device $device }
            $device
        }
        return
    }

    throw 'Get-DefenderDcDevice: -Watch is not implemented yet.'
}
