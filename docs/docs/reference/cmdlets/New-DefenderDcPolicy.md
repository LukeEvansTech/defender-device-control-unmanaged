# New-DefenderDcPolicy

## SYNOPSIS
Craft a custom Defender Device Control policy XML set from simple
per-class restriction parameters.

## SYNTAX

```
New-DefenderDcPolicy [-Usb <String[]>] [-Wpd <String[]>] [-Optical <String[]>]
    [-AllowHardwareId <String[]>] [-AllowDevice <PSCustomObject[]>]
    [-AllowDeviceFile <String>] [-OutputPath <String>] [-PolicyName <String>]
    [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Generates the same three-file policy shape this module ships
(PolicyGroups.xml, PolicyRules.Audit.xml, PolicyRules.Enforce.xml) so
the audit-first-then-enforce workflow stays a one-flag switch at apply
time. Pure generation: no registry access, no elevation, runs on any
platform. Apply the result with Set-DefenderDcPolicy (pipeline or
-GroupsXmlPath/-RulesXmlPath).

Group/rule/entry GUIDs are deterministic (hash-derived from stable
seeds), so regenerating the same policy yields byte-identical XML.

## EXAMPLES

### EXAMPLE 1
```
New-DefenderDcPolicy -Usb ReadOnly,DenyExecute -Wpd ReadOnly -OutputPath .\policy\
```

USB read-only with no execute, WPD read-only; XML pair written to .\policy\.

### EXAMPLE 2
```
Get-DefenderDcDevice -Watch -OutFile .\approved.json
New-DefenderDcPolicy -Usb ReadOnly -AllowDeviceFile .\approved.json -OutputPath .\policy\ |
    Set-DefenderDcPolicy -Mode Audit
```

Capture approved sticks, craft a policy exempting them, apply in Audit mode.

### EXAMPLE 3
```
New-DefenderDcPolicy -Usb Block -Optical Block -AllowHardwareId 'USBSTOR\DiskKingstonDataTraveler_3.0'
```

Block USB and optical entirely except Kingston DataTraveler 3.0 models.

## PARAMETERS

### -Usb
Restriction flags for removable storage (RemovableMediaDevices):
ReadOnly, DenyExecute, Block, Allow. ReadOnly+DenyExecute may combine;
Block and Allow are exclusive.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Wpd
Restriction flags for WPD/MTP devices (phones, cameras). Same
vocabulary as -Usb.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Optical
Restriction flags for CD/DVD drives. Same vocabulary as -Usb.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -AllowHardwareId
Hardware-ID strings exempted from all restrictions (model-wide match).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: @()
Accept pipeline input: False
Accept wildcard characters: False
```

### -AllowDevice
Device objects from Get-DefenderDcDevice (pipeline-friendly). Each
contributes its InstancePathId (serial-specific match).

```yaml
Type: PSCustomObject[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -AllowDeviceFile
Path to a JSON device list written by Get-DefenderDcDevice -OutFile.

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

### -OutputPath
Directory for the generated XML files. Created if missing. Defaults
to the current directory.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: .
Accept pipeline input: False
Accept wildcard characters: False
```

### -PolicyName
Label woven into group/rule names. Defaults to 'Custom policy'.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Custom policy
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### PSCustomObject
Device records from Get-DefenderDcDevice accepted via pipeline (ByValue).
Each record's InstancePathId is added to the approved-devices exception group.

## OUTPUTS

### PSCustomObject with type name DefenderDeviceControlUnmanaged.PolicyFiles
###   GroupsXmlPath       - Absolute path to the written PolicyGroups.xml
###   AuditRulesXmlPath   - Absolute path to the written PolicyRules.Audit.xml
###   EnforceRulesXmlPath - Absolute path to the written PolicyRules.Enforce.xml

## NOTES

## RELATED LINKS

[https://lukeevanstech.github.io/defender-device-control-unmanaged/](https://lukeevanstech.github.io/defender-device-control-unmanaged/)
