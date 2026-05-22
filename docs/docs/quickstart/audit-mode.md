# Audit mode

Apply the policy in Audit mode first. Audit logs every event that Enforce
would have blocked, but it does not block anything. This gives you a
concrete record that the policy parses correctly, the Defender engine
activates, and your rules cover the device classes you intend -- without
any disruption to users or ongoing work.

## Why audit before enforce

Skipping audit and going straight to Enforce on an untested machine
carries two risks. First, if the engine has not activated (see
[MDE attach gate](../concepts/mde-attach-gate.md)), Enforce silently does
nothing -- the only signal is `DeviceControlState=Disabled` in
`Get-MpComputerStatus`. Second, if your custom XML has a misconfigured
access mask, Audit lets you observe the matched events before you commit
to blocking behaviour. Spending a few minutes in Audit eliminates both
failure modes.

## Preview what will happen (WhatIf)

Before writing anything to the registry, run with `-WhatIf` to see the
planned writes:

```powershell
Set-DefenderDcPolicy -Mode Audit -WhatIf
```

Output lists all 5 planned registry writes and confirms which XML files
will be registered. No changes are made.

## Apply Audit mode

```powershell
Set-DefenderDcPolicy -Mode Audit
```

The cmdlet:

1. Validates `PolicyGroups.xml` and `PolicyRules.Audit.xml` through
   `MpCmdRun.exe -DeviceControl -TestPolicyXml`. Malformed XML is
   rejected before any registry write.
2. Writes 5 registry values under
   `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\`, with
   `Features\DeviceControlEnabled=1` written last so the master toggle
   only flips after all policy paths are in place.
3. Runs `gpupdate /force` to signal Defender to re-read the policy
   surface.
4. Queries `Get-MpComputerStatus` and reports the resulting
   `DeviceControlState`.

Expected output ends with:

```
[OK] Audit policy applied. DeviceControlState=Audit
```

## What just happened

Five registry writes were made and `gpupdate` triggered an engine reload.
The Defender engine read the new policy values, loaded the Groups and
Rules XML files from the registered paths, and transitioned
`DeviceControlState` to `Audit`. From this point, any USB write attempt
is logged as a `RemovableStoragePolicyTriggered` event in Defender XDR
Advanced Hunting, but the write is allowed to complete.

If you see `DeviceControlState=Disabled` instead of `Audit`, the
registry writes succeeded but the engine has not activated. See
[MDE attach gate](../concepts/mde-attach-gate.md) for the diagnosis
steps.

## Next steps

Proceed to [Verify](verify.md) to confirm the policy state with
`Test-DefenderDcPolicy` and run a live USB-stick test.
