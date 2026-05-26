# Get-DefenderDcPolicy

## SYNOPSIS
Return the current Defender Device Control policy state as a structured object.

## SYNTAX

```
Get-DefenderDcPolicy [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads the canonical registry surface (under HKLM\SOFTWARE\Policies\Microsoft\
Windows Defender\Device Control + Features\DeviceControlEnabled) and the
Defender engine view via Get-MpComputerStatus; emits a \[pscustomobject\]
suitable for piping or scripting.
Use Test-DefenderDcPolicy for a PASS/FAIL
summary instead.

## EXAMPLES

### EXAMPLE 1
```
Get-DefenderDcPolicy | Format-List
```

Read the current policy state and format as a list.

### EXAMPLE 2
```
$policy = Get-DefenderDcPolicy
if ($policy.Mode -eq 'Enforce') { Write-Host 'Currently enforcing.' }
```

Branch on the current mode.

## PARAMETERS

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

### PSCustomObject with properties:
###   Mode                              - 'Audit' | 'Enforce' | 'Off' (derived from Entry Types in the Rules XML)
###   FeaturesDeviceControlEnabled      - 0/1 or $null if absent
###   DefaultEnforcement                - 0/1 or $null
###   SecuredDevicesConfiguration       - string or $null
###   PolicyGroupsXmlPath               - string or $null
###   PolicyRulesXmlPath                - string or $null
###   DeviceControlState                - 'Enabled' / 'Disabled' / etc. from engine
###   DeviceControlPoliciesLastUpdated  - `[datetime]` or $null
## NOTES

## RELATED LINKS

[https://lukeevanstech.github.io/defender-device-control-unmanaged/](https://lukeevanstech.github.io/defender-device-control-unmanaged/)

