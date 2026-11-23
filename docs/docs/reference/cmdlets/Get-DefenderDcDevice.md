# Get-DefenderDcDevice

## SYNOPSIS

Capture the hardware identifiers of removable, WPD, and optical
devices for Device Control policy crafting.

## SYNTAX

```text
Get-DefenderDcDevice [-Watch] [-TimeoutSeconds <Int32>] [-OutFile <String>]
    [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION

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

## EXAMPLES

### EXAMPLE 1

```powershell
Get-DefenderDcDevice
```

List currently-connected removable/WPD/optical devices.

### EXAMPLE 2

```powershell
Get-DefenderDcDevice -Watch -OutFile .\approved.json
```

Plug approved sticks in one by one; each is printed and appended to
approved.json. Ctrl+C when done.

### EXAMPLE 3

```powershell
Get-DefenderDcDevice -Watch -TimeoutSeconds 60 |
    New-DefenderDcPolicy -Usb ReadOnly -OutputPath .\policy\
```

Capture for one minute, then craft a policy exempting what arrived.

## PARAMETERS

### -Watch

Subscribe to device-arrival events and emit devices as they are
plugged in, instead of a one-shot snapshot.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -TimeoutSeconds

Stop watching after this many seconds. Only valid with -Watch.
Without it, -Watch runs until Ctrl+C.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases: Timeout

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutFile

JSON file to append captured devices to (created on first capture).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

`PSCustomObject` with type name `DefenderDeviceControlUnmanaged.Device`
containing:

- **FriendlyName** - Display name of the device
- **Class** - Device class: 'Usb' | 'Wpd' | 'Optical'
- **InstancePathId** - Full PnP instance path (serial-specific, use in policy
  exceptions)
- **HardwareIds** - Array of hardware ID strings (model-wide, use with
  -AllowHardwareId)
- **VidPid** - USB vendor/product ID string (e.g. 'VID_0951&PID_1666'), or
  $null
- **SerialNumber** - Extracted serial number segment from the instance path
- **CapturedAt** - ISO-8601 UTC timestamp of when the record was captured

## NOTES

## RELATED LINKS

[https://lukeevanstech.github.io/defender-device-control-unmanaged/](https://lukeevanstech.github.io/defender-device-control-unmanaged/)
