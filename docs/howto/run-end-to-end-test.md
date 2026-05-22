# Run end-to-end USB test

`Invoke-DefenderDcUsbTest` automates the bracket work around a manual USB write attempt:
it applies the policy at your chosen mode, pauses for you to do the physical test, reads
back any local event-log evidence, then restores the pre-test state. This is the fastest
way to confirm the engine is actually enforcing (or auditing) on a live device.

---

## Run the test

Plug in a USB stick first so the drive letter is known, then run:

```powershell
Invoke-DefenderDcUsbTest -Drive E: -StartMode Audit
```

To test block behaviour:

```powershell
Invoke-DefenderDcUsbTest -Drive E: -StartMode Enforce
```

The `-Drive` parameter accepts `E` or `E:` -- the trailing colon is stripped
automatically.

---

## What the cmdlet does (seven phases)

**[1/7] Pre-flight**
Checks that the Defender AM service is enabled and the Sense service is Running. A
non-running Sense service means MDE is not attached and the engine will not act on the
policy.

**[2/7] Capture pre-state**
Reads the current Device Control mode with `Get-DefenderDcPolicy` and records it.
This is the mode the cmdlet will restore at the end (unless `-KeepDcApplied` is set).

**[3/7] Apply DC at StartMode**
Calls `Set-DefenderDcPolicy -Mode <StartMode>` with the shipped starter XMLs. If you
want to test custom XML, apply it yourself before calling this cmdlet and use
`-KeepDcApplied` to prevent rollback.

**[4/7] Verify static state**
Calls `Test-DefenderDcPolicy -ExpectMode <StartMode>` and records the result. A FAIL
here means the registry is not in the expected state and the manual test result would
be unreliable.

**[5/7] Operator interactive test**
The script pauses and prints instructions:

```
  Action required:
    1. Unplug the USB stick from E: (if currently mounted).
    2. Plug it back in. Wait for the drive letter to appear.
    3. Open a file from E: (read should always work).
    4. Try to copy a file TO E:.
         Audit:   succeeds, telemetry recorded in Defender XDR.
         Enforce: fails with 'The media is write protected'.
```

Press **Enter** when you are done with the manual test.

**[6/7] Event-log lookup**
After you press Enter, the cmdlet reads the last 100 events from the
`Microsoft-Windows-Windows Defender/Operational` log and filters for IDs
1109, 1110, and 1111 created in the two minutes before you pressed Enter. It prints the
count and timestamps. A count of zero is informational, not a failure.

**[7/7] Restore**
Restores the pre-test DC mode unless `-KeepDcApplied` is set or the pre-test mode
already matches the StartMode. Restoration calls `Set-DefenderDcPolicy -Mode <preMode>`.

---

## Reading the event-log results

Events 1109, 1110, and 1111 appear in the `Microsoft-Windows-Windows Defender/Operational`
log on older MDE builds. On modern MDE builds, Device Control events route exclusively
to Defender XDR Advanced Hunting and do not appear locally. A local count of zero is
therefore normal and expected.

To find the evidence in Defender XDR, go to
[security.microsoft.com](https://security.microsoft.com) > **Hunting** >
**Advanced Hunting** and run:

```kql
DeviceEvents
| where ActionType == 'RemovableStoragePolicyTriggered'
```

Filter by `DeviceName` and the time window of your test.

![Advanced Hunting query](../media/screenshots/S4-advanced-hunting.png)

---

## Leaving the test mode in place

By default the cmdlet rolls back to whatever DC mode was active before the test. To
leave the test mode running after the script finishes, add `-KeepDcApplied`:

```powershell
Invoke-DefenderDcUsbTest -Drive E: -StartMode Enforce -KeepDcApplied
```

---

## Return object

The cmdlet returns a `pscustomobject` with:

| Property | Description |
|---|---|
| `Failures` | Count of PASS/FAIL assertions that failed |
| `TranscriptPath` | Path to the full session transcript |
| `StartMode` | The mode applied during the test |
| `EventsCaptured` | Number of 1109/1110/1111 events found locally |
| `PreTestMode` | The DC mode before the test started |

---

## Related

- [mde-attach-gate concept](../concepts/mde-attach-gate.md)
- [Invoke-DefenderDcUsbTest reference](../reference/cmdlets/Invoke-DefenderDcUsbTest.md)
