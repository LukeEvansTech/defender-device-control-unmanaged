# MDE attach gate

Registry writes succeed on any Windows 11 Enterprise machine, regardless
of whether it is onboarded to Microsoft Defender for Endpoint. The
Defender engine, however, only activates Device Control policy on a
machine that has completed MDE onboarding. This distinction matters:
`Set-DefenderDcPolicy` can complete without error, all five registry
values can be present and correct, and yet `DeviceControlState` remains
`Disabled`.

This is not a bug. It is a SKU and license gate inside the Defender
engine. The engine checks three conditions before it transitions
`DeviceControlState` from `Disabled` to `Audit` or `Enforce`.

## The three activation conditions

![MDE attach gate decision flow](../media/diagrams/D3-mde-attach-gate.svg)

| Condition | How to check | Expected value |
|-----------|-------------|----------------|
| Sense service is running | `Get-Service Sense` | `Status=Running`, `StartType=Automatic` |
| OnboardingState is 1 | `Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status'` | `OnboardingState=1` |
| OrgId is populated | Same key as above | `OrgId=<non-empty GUID>` |

All three must be true simultaneously. A machine where Sense is running
but OrgId is empty (for example, a machine where onboarding was started
but not completed) stays at `DeviceControlState=Disabled`.

## Quick check sequence

From an elevated PowerShell window:

```powershell
Get-Service Sense | Select-Object Name, Status, StartType

Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' |
    Select-Object OnboardingState, OrgId
```

Expected output on a fully onboarded machine:

```
Name   Status   StartType
----   ------   ---------
Sense  Running  Automatic

OnboardingState : 1
OrgId           : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

If `OnboardingState` is 0 or the key does not exist, the machine has
not completed onboarding.

## What happens if you apply DC without MDE

The apply operation completes cleanly. `MpCmdRun.exe -DeviceControl
-TestPolicyXml` passes against the XML files. All five registry values
are written. `gpupdate /force` runs. Then `Get-MpComputerStatus` returns
`DeviceControlState=Disabled` because none of the three engine
conditions are met.

No writes fail, no errors are thrown, and no devices are blocked. The
policy is registered but inert.

## If you need to onboard

`Invoke-DefenderDcOnboarding` wraps the Microsoft-provided local
onboarding script. It auto-detects the per-tenant ZIP in
`$env:USERPROFILE\Downloads\`, extracts the inner `.cmd`, runs it
elevated, waits for Sense to come up, and verifies all three activation
conditions before returning. See
[Onboard to MDE](../howto/onboard-to-mde.md) for the full procedure.

Note: offboarding from MDE is out of scope for this module. To offboard
a device, use the offboarding package from `security.microsoft.com`.
