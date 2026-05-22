# KB-004: DeviceControlState stays Enabled after Set-DefenderDcPolicy -Mode Off

**Status:** Active
**Applies to:** DefenderDeviceControlUnmanaged
**Severity:** Low

## Symptom

You run:

```powershell
Set-DefenderDcPolicy -Mode Off
```

The cmdlet reports success. The Defender Device Control registry tree
is gone:

```powershell
Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control'
# False
```

But the engine state still reads as if a policy were active:

```powershell
(Get-MpComputerStatus).DeviceControlState
# Enabled (or Audit / Enforce)
```

Re-running the verifier within 60 seconds of Off shows `Enabled` with
a clean registry -- apparent inconsistency.

## Cause

Defender DC has a cached, in-process view of policy state that
refreshes on a timer rather than on every registry change. After the
policy registry tree is removed, the engine takes time -- observed
**>60 seconds**, occasionally longer -- to notice and flip its
`DeviceControlState` to `Disabled`.

During this settle window:

- The **registry is authoritative**. If the policy tree is gone,
  enforcement is gone -- the engine cache is stale but does not
  re-deny based on policy it no longer holds.
- Real USB writes succeed normally (try it).
- The cached `DeviceControlState` is the only stale signal.

This is engine behaviour, not a bug in the cmdlet. `Set-DefenderDcPolicy`
writes a manifest with `Features\DeviceControlEnabled` as the last
entry on apply (so enforcement only flips after every policy value
lands) and removes the parent key on Off (so the engine sees a clean
slate immediately on its next refresh cycle).

## Fix

Wait. The engine refreshes within 1-2 minutes. There is no command
that forces an immediate refresh of the DC cache short of restarting
the Defender service, which the in-place policies on a Tamper-Protected
box may not permit.

For automated tooling, `Test-DefenderDcPolicy -ExpectMode Off`
explicitly treats residual `Enabled` with a clean registry as
**INFO-not-FAIL**:

```
[INFO] Engine cache shows DeviceControlState=Enabled but registry is clean. Settling -- re-check in 60s.
```

This is intentional; the test does not fail because the authoritative
state (registry) is correct.

If you must confirm the cache has refreshed before handover:

```powershell
Start-Sleep -Seconds 60
(Get-MpComputerStatus).DeviceControlState
```

Expected after settle: `Disabled`.

## How to validate the fix

```powershell
# Registry-side (authoritative -- should always be clean immediately after Off)
Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control'

# Engine-side (stale until settle)
(Get-MpComputerStatus).DeviceControlState
```

After 60-120 seconds, both should show no policy / Disabled.

## See also

- [KB-005: Build 28000 CIM quirks](005-build-28000-cim-quirks.md) --
  related: how the verifier reads the engine state defensively.
- [How-to: Roll back](../../howto/roll-back.md)
- Source: `src/DefenderDeviceControlUnmanaged/Public/Test-DefenderDcPolicy.ps1`
