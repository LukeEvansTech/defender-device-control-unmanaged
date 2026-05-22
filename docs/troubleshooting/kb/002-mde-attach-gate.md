# KB-002: Defender Device Control requires MDE attach to activate

**Status:** Active
**Applies to:** DefenderDeviceControlUnmanaged
**Severity:** Critical

## Symptom

`Set-DefenderDcPolicy -Mode Enforce` reports success. The registry
surface is populated. `gpupdate /force` completes cleanly.
USB writes still succeed -- the policy is not being enforced.

Diagnostic check:

```powershell
(Get-MpComputerStatus).DeviceControlState
```

Returns `Disabled` (not `Audit` or `Enforce`).

This is **not** a misconfiguration of the policy artefacts. The cmdlet
has done its job. The Defender engine is gated by something else.

## Cause

Microsoft Defender Device Control is a feature of **Microsoft Defender
for Endpoint** (MDE). The engine accepts the GPO-shaped policy registry
on any Windows 11 Enterprise box -- and you can verify it has read the
policy successfully:

- Each registry write is acknowledged with event ID 5007 under
  `Microsoft-Windows-Windows Defender/Operational`.
- `(Get-MpComputerStatus).DeviceControlPoliciesLastUpdated` advances
  to the time of the last `gpupdate /force`.

But enforcement is **license-gated**. The engine will not flip
`DeviceControlState` from `Disabled` to `Audit`/`Enforce` unless the
endpoint is onboarded to one of:

- Microsoft Defender for Endpoint **Plan 1**
- Microsoft Defender for Endpoint **Plan 2**
- Microsoft Defender for Business (the SMB-tier SKU)

On a standalone Windows 11 Enterprise box with no MDE onboarding, the
module applies policy cleanly but the feature stays dormant. The
registry, policy XML validation, and gpupdate steps are all fine.

## Fix

Onboard the endpoint to MDE to activate enforcement.

1. Obtain the per-tenant onboarding ZIP from
   `https://security.microsoft.com` -> Settings -> Endpoints ->
   Onboarding. The ZIP is tenant-specific and time-limited
   (approximately 30 days).
2. Drop the ZIP into `$env:USERPROFILE\Downloads\` on the target box
   (or pass `-OnboardingScript <path>` to override auto-detection).
3. Run elevated:

```powershell
Invoke-DefenderDcOnboarding
```

4. Wait for the post-flight to confirm `Sense` is Running+Automatic
   and `OnboardingState=1`. The cmdlet auto-detects any
   `*WindowsDefenderATPOnboarding*.zip` in Downloads and handles
   variant filename prefixes that Microsoft generates per tenant.
5. Re-run `Test-DefenderDcPolicy` to confirm the engine has now
   flipped to your previously-applied DC mode.

If MDE licensing is not available for this deployment, Defender Device
Control cannot be activated on the endpoint. In that case,
this module is the wrong tool for the job -- consider Intune
Configuration Profiles or Group Policy (GPMC) to push equivalent
Removable Storage Access registry values via the in-box kernel-filter
mechanism, which has no MDE dependency.

## How to validate the fix

```powershell
$s = Get-MpComputerStatus
$s.DeviceControlState
$s.DeviceControlPoliciesLastUpdated
```

Expected: `DeviceControlState` is `Audit` or `Enforce` (matching the
mode you applied), `DeviceControlPoliciesLastUpdated` is recent
(within the last few minutes).

## See also

- [How-to: Onboard to MDE](../../howto/onboard-to-mde.md)
- [Concept: MDE attach gate](../../concepts/mde-attach-gate.md)
- [FAQ: Do I need a specific Defender SKU?](../../faq.md#q-license-sku)
