function ConvertTo-DcDevice {
    <#
    .SYNOPSIS
        Convert a Win32_PnPEntity instance into the module's device record.
    .DESCRIPTION
        Classifies the entity into the device classes this module tracks
        (Usb removable storage, Wpd, Optical) and extracts the Device
        Control-usable descriptors. Returns nothing for untracked classes,
        so callers can pipe a full PnP enumeration through it. Accepts any
        object with Name/PNPDeviceID/PNPClass/HardwareID properties (tests
        pass fakes).
    .PARAMETER PnpEntity
        A Win32_PnPEntity CIM instance or shape-compatible object.
    .EXAMPLE
        Get-CimInstance Win32_PnPEntity | ForEach-Object { ConvertTo-DcDevice -PnpEntity $_ }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $PnpEntity
    )

    Set-StrictMode -Version Latest

    $pnpId = [string]$PnpEntity.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($pnpId)) { return }

    $pnpClassProp = $PnpEntity.PSObject.Properties['PNPClass']
    $pnpClass = if ($null -ne $pnpClassProp) { [string]$pnpClassProp.Value } else { '' }

    # USBSTOR prefix beats PNPClass: removable disks report PNPClass DiskDrive.
    $class = if ($pnpId -like 'USBSTOR\*') { 'Usb' }
             elseif ($pnpClass -eq 'CDROM') { 'Optical' }
             elseif ($pnpClass -eq 'WPD')   { 'Wpd' }
             else { $null }
    if ($null -eq $class) { return }

    $hardwareIdsProp = $PnpEntity.PSObject.Properties['HardwareID']
    $hardwareIds = if ($null -ne $hardwareIdsProp -and $null -ne $hardwareIdsProp.Value) {
        @($hardwareIdsProp.Value | ForEach-Object { [string]$_ })
    } else { @() }

    # VID/PID lives on the USB device node; USBSTOR children often lack it.
    $vidPid = $null
    foreach ($candidate in (@($pnpId) + $hardwareIds)) {
        if ($candidate -match '(VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4})') {
            $vidPid = $Matches[1].ToUpperInvariant()
            break
        }
    }

    # Instance path convention: serial is the last path segment, before any
    # '&N' disambiguator (e.g. ...\E0D55EA574DBF750E97B0A14&0).
    $serial = ($pnpId.Split('\')[-1]).Split('&')[0]

    [pscustomobject]@{
        PSTypeName     = 'DefenderDeviceControlUnmanaged.Device'
        FriendlyName   = [string]$PnpEntity.Name
        Class          = $class
        InstancePathId = $pnpId
        HardwareIds    = $hardwareIds
        VidPid         = $vidPid
        SerialNumber   = $serial
        CapturedAt     = (Get-Date).ToUniversalTime().ToString('o')
    }
}
