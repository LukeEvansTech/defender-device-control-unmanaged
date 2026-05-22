# Test-DefenderDcPolicyXml

## SYNOPSIS
Validate a Defender Device Control policy XML before deploying it.

## SYNTAX

```
Test-DefenderDcPolicyXml [-Path] <String> [-Kind] <String> [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Three-layer validation for a Groups or Rules policy XML:
  1.
Structural parse - is it valid XML, with the expected root element?
  2.
Format constraints - no UTF-8 BOM, no \<?xml ...
?\> declaration,
     Name as child element (not attribute) on PolicyRule, Options
     bitmask in 0..3.
  3.
Engine-side - MpCmdRun.exe -DeviceControl -TestPolicyXml (skipped
     silently if MpCmdRun.exe is not on this box, e.g.
CI runners).

Each layer fails with a specific, named error so authors of custom XML
know exactly which constraint they violated.
Returns $true on full pass,
$false on any failure (plus a Write-Error describing which constraint).

## EXAMPLES

### EXAMPLE 1
```
Test-DefenderDcPolicyXml -Path .\MyGroups.xml -Kind Groups
```

Validate a custom Groups XML.

### EXAMPLE 2
```
Test-DefenderDcPolicyXml -Path .\MyRules.xml -Kind Rules
```

Validate a custom Rules XML, including engine-side check on Windows.

## PARAMETERS

### -Path
Path to the XML file to validate.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Kind
Groups (for a PolicyGroups XML) or Rules (for a PolicyRules XML).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

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

### System.Boolean
## NOTES

## RELATED LINKS

[https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/validate-custom-xml/](https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/validate-custom-xml/)

