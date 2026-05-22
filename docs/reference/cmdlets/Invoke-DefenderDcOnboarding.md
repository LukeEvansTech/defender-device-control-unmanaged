# Invoke-DefenderDcOnboarding

## SYNOPSIS
Onboard this Windows host to Microsoft Defender for Endpoint using the
per-tenant local-script deployment method.

## SYNTAX

```
Invoke-DefenderDcOnboarding [[-OnboardingScript] <String>] [[-SkipPostFlightWait] <Int32>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Wraps Microsoft's per-tenant onboarding .cmd with pre-flight checks,
auto-detection of the onboarding ZIP in $env:USERPROFILE\Downloads\,
extraction, elevated execution, and post-flight verification.

Pre-flight: Defender AM service enabled, Sense service present, not
already onboarded.
Post-flight: Sense Running + Automatic, OnboardingState=1, OrgId
populated.

Requires administrator elevation.
Captures a transcript under
$env:LOCALAPPDATA\DefenderDeviceControlUnmanaged\.

## EXAMPLES

### EXAMPLE 1
```
Invoke-DefenderDcOnboarding
```

Auto-detect the onboarding ZIP in Downloads and run it.

### EXAMPLE 2
```
Invoke-DefenderDcOnboarding -OnboardingScript C:\onboard\WindowsDefenderATPOnboardingPackage.zip
```

Explicitly pass the ZIP path.

## PARAMETERS

### -OnboardingScript
Optional path to either the per-tenant ZIP (e.g.
WindowsDefenderATPOnboardingPackage.zip) or the extracted
WindowsDefenderATP*OnboardingScript.cmd.
If not supplied, searches
$env:USERPROFILE\Downloads\ for files matching
'*WindowsDefenderATPOnboarding*.zip' and uses the newest match.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SkipPostFlightWait
Seconds to wait between the onboarding script exit and the post-flight
checks.
Defender service start and registry markers are async.
Default 30.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: 30
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

[https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/onboard-to-mde/](https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/onboard-to-mde/)

