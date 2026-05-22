# Invoke-DefenderDcUsbTest

## SYNOPSIS
End-to-end USB stick test driver for the Defender Device Control policy.

## SYNTAX

```
Invoke-DefenderDcUsbTest [-Drive] <String> [[-StartMode] <String>] [-KeepDcApplied]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Operator-facing test that brackets a manual USB stick write attempt with
DC policy apply and rollback.
Captures a transcript and reads back the
last 2 minutes of Defender 1109/1110/1111 events (softened to
informational on modern MDE builds where events route to Defender XDR
Advanced Hunting only).

Phases:
  1.
Pre-flight: Defender and Sense state.
  2.
Capture pre-state of DC policy.
  3.
Apply DC at -StartMode.
  4.
Verify static state.
  5.
Operator interactive: replug stick, attempt write, observe result.
  6.
Read event-log signal (best-effort; zero events is not a failure).
  7.
Restore DC to pre-test state (unless -KeepDcApplied).

Requires administrator elevation.

## EXAMPLES

### EXAMPLE 1
```
Invoke-DefenderDcUsbTest -Drive E:
```

Run an Audit-mode USB test against E: drive.

### EXAMPLE 2
```
Invoke-DefenderDcUsbTest -Drive E: -StartMode Enforce -KeepDcApplied
```

Run an Enforce-mode test and leave Enforce active afterwards.

## PARAMETERS

### -Drive
Drive letter of the USB stick to test, e.g.
'E' or 'E:'.
A trailing
colon is accepted and stripped automatically.

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

### -StartMode
DC mode to apply during the test.
Default 'Audit' (safer first proof).
'Enforce' blocks writes and fires deny events.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: Audit
Accept pipeline input: False
Accept wildcard characters: False
```

### -KeepDcApplied
Switch.
If set, skip the final rollback and leave DC at -StartMode after
the test completes.
Default: rollback to whatever DC mode was active
before the test began.

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

### System.Management.Automation.PSObject
## NOTES

## RELATED LINKS

[https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/run-end-to-end-test/](https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/run-end-to-end-test/)

