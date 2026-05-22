# KB-005: Get-MpPreference and CIM property quirks on Windows 11 build 28000

**Status:** Active
**Applies to:** DefenderDeviceControlUnmanaged (verifier)
**Severity:** Low

## Symptom

`Test-DefenderDcPolicy` aborts with a stack trace ending in:

```
PropertyNotFoundException: The property 'DeviceControlEnabled' cannot be found on this object.
```

Or attempts to read DC state via `Get-MpPreference` show the
`DeviceControl*` family of properties is absent entirely:

```powershell
Get-MpPreference | Get-Member | Where-Object Name -like 'DeviceControl*'
# (no output)
```

## Cause

On **Windows 11 build 28000** (the Canary channel, observed 2026-05),
Microsoft's CIM provider for Defender (`MSFT_MpPreference`) does not
expose the `DeviceControl*` set of preference fields that
`Get-MpPreference` returns on production builds (22H2 / 23H2 / 24H2).

The fields exist conceptually -- the engine respects them -- but the
in-band CIM marshalling layer omits them on this Canary build.
Compounding this, PowerShell's strict-mode CIM accessor raises
`PropertyNotFoundException` on property reads against properties that
the underlying object did not emit, instead of returning `$null`.

Result: a naive `Get-MpPreference | Select-Object -ExpandProperty DeviceControlEnabled`
blows up on build 28000 even though the engine is healthy.

## Fix

This module's verifier (`Test-DefenderDcPolicy`) avoids the issue by:

1. Reading DC state from `Get-MpComputerStatus` instead of
   `Get-MpPreference`. The fields `DeviceControlState` and
   `DeviceControlPoliciesLastUpdated` are present on build 28000.
2. Defensive property probing via `$obj.PSObject.Properties['Name']`
   instead of bare dotted access, which returns `$null` (not an
   exception) when the property is absent.

If you are writing custom diagnostics on build 28000, use the same
pattern:

```powershell
# Bad -- throws on build 28000 if property is absent
$state = (Get-MpPreference).DeviceControlEnabled

# Good -- returns $null if absent, value if present
$status = Get-MpComputerStatus
$state = if ($status.PSObject.Properties['DeviceControlState']) {
    $status.DeviceControlState
} else {
    $null
}
```

On production builds (22H2 / 23H2 / 24H2), the defensive form still
works -- it just always finds the property. No need to detect the build
number first.

## How to validate the fix

```powershell
# Reproduce the bad case (will throw on 28000 strict-mode)
(Get-MpPreference).DeviceControlEnabled  # PropertyNotFoundException expected on 28000

# Confirm Get-MpComputerStatus exposes what we actually need
$s = Get-MpComputerStatus
$s.PSObject.Properties['DeviceControlState'].Value               # State enum
$s.PSObject.Properties['DeviceControlPoliciesLastUpdated'].Value # DateTime
```

Expected: the second block returns useful values; the first throws on
build 28000 and succeeds on production builds.

## See also

- [KB-004: Engine state stickiness](004-engine-state-stickiness.md) --
  related: even when you read the state correctly, it lags the
  registry on policy removal.
- Source: `src/DefenderDeviceControlUnmanaged/Public/Test-DefenderDcPolicy.ps1`
- Microsoft Learn: <https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus>
