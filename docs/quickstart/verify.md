# Verify

`Test-DefenderDcPolicy` gives you a static picture of the registry and
engine state. The USB-stick recipe below gives you the dynamic
behavioural confirmation. Run both.

## Static verification with Test-DefenderDcPolicy

Pass the mode you expect the machine to be in:

```powershell
Test-DefenderDcPolicy -ExpectMode Audit
# or
Test-DefenderDcPolicy -ExpectMode Enforce
```

The cmdlet checks each part of the canonical policy state and prints
a PASS or FAIL line for each:

```
[PASS] DeviceControlEnabled registry value = 1
[PASS] DefaultEnforcement registry value = 1
[PASS] SecuredDevicesConfiguration covers RemovableMediaDevices|CdRomDevices|WpdDevices
[PASS] PolicyGroups path registered and file exists
[PASS] PolicyRules path registered and file exists
[PASS] DeviceControlState = Audit
[PASS] DeviceControlPoliciesLastUpdated within last 10 minutes
...
```

The cmdlet exits with code 0 when all checks pass, and non-zero if any
check fails. This makes it suitable for use in scripts or CI where you
want a hard stop on failure.

![Test PASS output](../media/screenshots/S2-test-pass.png)

If any line shows FAIL, the label identifies which registry value or
engine property is wrong. The most common failure after a fresh apply is
`DeviceControlState = Disabled` -- meaning the registry is correct but
the engine has not activated. See
[MDE attach gate](../concepts/mde-attach-gate.md) for diagnosis steps.

## Dynamic verification: USB-stick recipe

Static checks confirm the policy was written; the USB-stick recipe
confirms the engine is actually enforcing it. Use a test stick, not a
production stick.

**Unplug and replug the stick first.** Already-mounted volumes keep
their pre-apply policy until the device handle closes. Replugging forces
a fresh mount under the current policy.

Then test by mode:

| Mode | Try a write | Expected | Try a read | Expected |
|------|-------------|----------|------------|----------|
| Audit | Copy a small file to the stick | Write succeeds | Open a file from the stick | Read succeeds |
| Enforce | Copy a small file to the stick | "The media is write protected" | Open a file from the stick | Read succeeds |
| Off | Copy a small file to the stick | Write succeeds | Open a file from the stick | Read succeeds |

A quick write test from PowerShell:

```powershell
# Replace E: with your stick's drive letter
"test" | Set-Content E:\ddcu-verify.txt
```

Under Enforce this throws `UnauthorizedAccessException: The media is
write protected.` Under Audit or Off it succeeds and you can delete the
file with `Remove-Item E:\ddcu-verify.txt`.

## Automated end-to-end test

For a ticketable record of the full apply-write-read-restore cycle, use
the end-to-end test cmdlet:

```powershell
Invoke-DefenderDcUsbTest -Drive E:
```

This cmdlet drives the full sequence automatically and captures a
transcript. See [Run the end-to-end test](../howto/run-end-to-end-test.md)
for the full walkthrough.

## Bug-hunting hint

If `Test-DefenderDcPolicy` reports `DeviceControlState=Disabled` despite
all registry checks passing, the engine is present but not consuming the
policy. This is almost always the MDE attach gate -- the Sense service
is not running or the device has not completed onboarding. See
[MDE attach gate](../concepts/mde-attach-gate.md) for the three
activation conditions and how to check each one.

## Next steps

The quickstart is complete. Explore the [Concepts](../concepts/registry-surface.md)
section for a deeper understanding of how the registry surface and policy
XML work, or go to [How-to guides](../howto/extend-device-categories.md)
to extend the shipped policy with additional device categories.
