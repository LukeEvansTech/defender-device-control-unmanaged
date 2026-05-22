# Enforce mode

Switch from Audit to Enforce when you have confirmed that the policy is
active and matching the expected device classes. Enforce replaces the
Audit rules XML with a Deny rules XML, so the Defender engine blocks
write and execute attempts rather than just logging them.

## Pre-flight: confirm Audit is working

Before flipping to Enforce, verify that Audit mode is genuinely active:

```powershell
Test-DefenderDcPolicy -ExpectMode Audit
```

All checks should return PASS and `DeviceControlState` should be `Audit`.
If any check fails, resolve it before proceeding -- see
[Verify](verify.md) for the full diagnostic recipe.

If `DeviceControlState=Disabled` is still showing after applying Audit,
the MDE attach gate has not been cleared. See
[MDE attach gate](../concepts/mde-attach-gate.md) before continuing.

## Apply Enforce mode

```powershell
Set-DefenderDcPolicy -Mode Enforce
```

The cmdlet follows the same sequence as Audit: pre-validates the Enforce
rules XML via `MpCmdRun.exe`, writes the same 5 registry values (with
the updated XML path for the rules file), then runs `gpupdate /force`.
The difference is entirely in the rules XML content -- `Type=Deny`
instead of `Type=AuditAllowed`. See
[Audit vs Enforce](../concepts/audit-vs-enforce.md) for a side-by-side
comparison.

Expected output ends with:

```
[OK] Enforce policy applied. DeviceControlState=Enforce
```

## What users will see

On any USB write attempt, the operation fails immediately with:

```
The media is write protected.
```

In File Explorer this appears as a toast notification from Windows
Security. In a PowerShell `Set-Content` or `Copy-Item` call, it surfaces
as an `UnauthorizedAccessException` with that string in the inner
message.

Read access is unchanged. Opening files from USB, reading directory
listings, and copying files off the stick all continue to work. The
policy denies writes and execute; it does not restrict reads.

Note: if the USB stick was already mounted when you applied Enforce, the
new policy may not take effect on that volume until the device is
unplugged and replugged. Unplug, wait a few seconds, then replug to
ensure the engine applies the new policy to a fresh mount.

## Rollback if needed

To drop back to Audit without removing the policy entirely:

```powershell
Set-DefenderDcPolicy -Mode Audit
```

To remove the policy completely:

```powershell
Set-DefenderDcPolicy -Mode Off
```

`-Mode Off` removes all 5 registry values and runs `gpupdate /force`.
The engine may continue reporting `DeviceControlState=Enforce` for up to
two minutes while it processes the removal -- this is normal. See
[engine state stickiness](../troubleshooting/kb/004-engine-state-stickiness.md)
if it persists beyond that window.

## Next steps

Proceed to [Verify](verify.md) to run `Test-DefenderDcPolicy -ExpectMode
Enforce` and complete the live USB-stick test.
