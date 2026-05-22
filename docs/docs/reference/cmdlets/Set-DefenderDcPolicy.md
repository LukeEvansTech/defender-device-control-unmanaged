# Set-DefenderDcPolicy

## SYNOPSIS
Apply or remove the Defender Device Control read-only USB policy on an
unmanaged Windows 11 device, using the canonical Local GPO registry
surface (file-path REG_SZ + XML, per WindowsDefender.admx).

## SYNTAX

```
Set-DefenderDcPolicy [-Mode] <String> [[-GroupsXmlPath] <String>] [[-RulesXmlPath] <String>]
 [-SkipMpCmdRunValidation] [-SkipGpUpdate] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Writes 5 registry values under HKLM\SOFTWARE\Policies\Microsoft\Windows
Defender\...
that point Defender at policy XMLs describing the device
groups and per-class deny rules.
By default, ships starter XMLs covering
removable storage, WPD/MTP, and optical drives.
Supply -GroupsXmlPath
and -RulesXmlPath to deploy your own.

Requires administrator elevation.
Requires MDE attach for the engine to
consume policy (registry writes succeed on any box; engine activation
requires Microsoft Defender for Endpoint).

## EXAMPLES

### EXAMPLE 1
```
Set-DefenderDcPolicy -Mode Audit -WhatIf
```

Preview the planned registry writes without applying.

### EXAMPLE 2
```
Set-DefenderDcPolicy -Mode Enforce
```

Apply policy in Enforce mode.

### EXAMPLE 3
```
Set-DefenderDcPolicy -Mode Enforce -GroupsXmlPath 'C:\MyPolicy\Groups.xml' -RulesXmlPath 'C:\MyPolicy\Rules.xml'
```

Deploy a custom policy XML pair.

### EXAMPLE 4
```
Set-DefenderDcPolicy -Mode Off
```

Remove the policy entirely.

## PARAMETERS

### -Mode
Audit (log without block), Enforce (block + log), or Off (remove policy).

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

### -GroupsXmlPath
Optional absolute path to a PolicyGroups.xml.
Defaults to the shipped
starter XML.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -RulesXmlPath
Optional absolute path to a PolicyRules.\<Mode\>.xml.
Defaults to the
shipped starter XML matching the selected -Mode.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SkipMpCmdRunValidation
Skip the engine-side XML preflight via MpCmdRun.exe -DeviceControl
-TestPolicyXml.
Off by default - validation recommended.

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

### -SkipGpUpdate
Skip the trailing gpupdate /force.
gpupdate is the canonical trigger
that makes Defender consume the policy.
Skipping leaves the registry
written but the engine may not pick up the policy until the next
OS-driven refresh.

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

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
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

## NOTES

## RELATED LINKS

[https://lukeevanstech.github.io/defender-device-control-unmanaged/](https://lukeevanstech.github.io/defender-device-control-unmanaged/)

