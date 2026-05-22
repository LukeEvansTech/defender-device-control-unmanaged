# No local event log on MDE builds (KB 003)

**Status:** Active
**Applies to:** DefenderDeviceControlUnmanaged
**Severity:** Medium

## Symptom

After applying Defender Device Control in Audit or Enforce mode, a
USB write is correctly blocked (Enforce) or correctly logged
(Audit), but `Get-WinEvent` against the Defender operational log
shows no per-deny or per-audit entries:

```powershell
Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' -FilterXPath "*[System[EventID=1110 or EventID=1111 or EventID=1109]]" -MaxEvents 10
```

Returns nothing, or only entries from older deployments.

Older Microsoft Learn pages describe events 1109 (audit), 1110 (deny),
1111 (write detected). On current MDE-onboarded builds (Defender
engine `4.18.26040`+), these events are not written locally.

## Cause

On MDE-onboarded endpoints running recent Defender builds, Device
Control event telemetry routes via **ETW** (Event Tracing for
Windows) directly to the Defender XDR cloud, not to the local
Windows event log. The 1109/1110/1111 event IDs are still emitted on
older non-MDE-onboarded builds, but on the MDE codepath they are
suppressed locally because the cloud channel is the primary consumer.

This is by design. What you do see locally:

- **Toast notifications** still fire client-side from Windows Security
  when a deny occurs.
- The user-visible **write error message** still surfaces. Under
  Defender DC Enforce, the message is:

```
The media is write protected.
```

## Fix

There is nothing to fix on the endpoint -- the absence of local events
is the expected state on MDE builds. To inspect per-event detail,
use **Advanced Hunting** in the Defender XDR portal.

1. Open `https://security.microsoft.com`.
2. Navigate to Hunting -> Advanced hunting.
3. Run this KQL query (substitute your hostname):

```kql
DeviceEvents
| where ActionType == "RemovableStoragePolicyTriggered"
| where DeviceName == "<hostname>"
| project Timestamp, ActionType, DeviceName, AdditionalFields, ActionFields=parse_json(AdditionalFields)
| top 50 by Timestamp desc
```

Telemetry latency from endpoint to portal is typically 5-15 minutes;
on a fresh deployment, wait at least 15 minutes before concluding
that an event is missing.

## How to validate the fix

After driving a USB write under Enforce, plus a 15-minute settle:

1. The KQL query above returns rows for the test events.
2. Each row's `AdditionalFields` JSON contains the rule ID
   (`PolicyRule`), the group ID (`PolicyRuleGroup`), and the deny
   reason.

Local-only verification (for boxes without portal access or before
the telemetry lands):

- Toast notification appeared on Enforce write attempt.
- `(Get-MpComputerStatus).DeviceControlState` returns `Enforce`.
- `(Get-MpComputerStatus).DeviceControlPoliciesLastUpdated` is recent.

## See also

- [How-to: Run end-to-end test](../../howto/run-end-to-end-test.md)
- Microsoft Learn:
  <https://learn.microsoft.com/en-us/defender-endpoint/advanced-hunting-deviceevents-table>
