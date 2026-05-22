# Test-DefenderDcPolicy

## SYNOPSIS
Verify the Defender Device Control policy state on this machine.

## SYNTAX

```
Test-DefenderDcPolicy [[-ExpectMode] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads registry + Defender engine state, prints PASS/FAIL per check,
returns boolean (true if all checks passed).
Prints a dynamic-test
recipe the operator can drive with a real USB stick.

## EXAMPLES

### EXAMPLE 1
```
Test-DefenderDcPolicy -ExpectMode Audit
```

Verify policy is in Audit mode and the engine has consumed it.

### EXAMPLE 2
```
Test-DefenderDcPolicy -ExpectMode Off
```

Verify the policy has been fully removed.

## PARAMETERS

### -ExpectMode
Audit, Enforce, or Off.
The state we expect to find.
Default Audit.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: Audit
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

[https://lukeevanstech.github.io/defender-device-control-unmanaged/](https://lukeevanstech.github.io/defender-device-control-unmanaged/)

