# Engineer runbook

This is the copy-and-run path for an engineer whose ticket says
"USB read-only on this Windows 11 box". Plan ~15 minutes from clean
shell to verified policy. Every command runs from an **elevated**
PowerShell prompt on the target machine.

## Context (the 30-second version)

Microsoft Defender Device Control is built into Windows 11 Enterprise.
It can deny USB write and execute while leaving USB read open. The
catch is that Microsoft's own deployment guidance assumes you have
Intune, domain GPO, or Configuration Manager. On an unmanaged box --
MDE-licensed, but not domain-joined and not in Intune -- none of those
deployment paths apply. This module writes the same registry surface
those tools would push, directly, from a single elevated PowerShell
prompt.

The default policy this runbook applies is:

| Action | Removable storage | Optical (CD/DVD) | WPD (phones, cameras) |
|---|---|---|---|
| **Read** | Allow | Allow | Allow |
| **Write** | Deny | Deny | Deny |
| **Execute** | Deny | Deny | n/a |

Read stays open so existing workflows that consume files from USB are
not disrupted. Write and execute are denied so the box cannot be used
to exfiltrate data or run an untrusted binary off removable media.
This is the most common "lock down USB" baseline.

## Pre-requisites

Before you start, confirm all four conditions on the target box:

| Check | How | Required value |
|---|---|---|
| Windows edition | `Get-ComputerInfo \| Select-Object WindowsProductName` | Windows 11 (or 10) **Enterprise** |
| PowerShell version | `$PSVersionTable.PSVersion` | 5.1 or later |
| MDE attach | `Get-Service Sense` | Status `Running`, StartType `Automatic` |
| Running elevated | Title bar of the prompt | Says "Administrator" |

If MDE attach is missing, complete onboarding first --
[Onboard to MDE](howto/onboard-to-mde.md) -- then come back. Registry
writes succeed without MDE attach, but the Defender engine will not
activate the policy and `DeviceControlState` stays at `Disabled`. See
[MDE attach gate](concepts/mde-attach-gate.md) for the failure mode in
detail.

## Step 1: Install the module

Two options. Use **A** unless the box can't reach the PowerShell Gallery.

**A. From the PowerShell Gallery (preferred):**

```powershell
Install-Module -Name DefenderDeviceControlUnmanaged -Scope CurrentUser
Import-Module DefenderDeviceControlUnmanaged
```

**B. Clone the repo and import locally (air-gapped or Gallery-blocked):**

```powershell
git clone https://github.com/LukeEvansTech/defender-device-control-unmanaged.git
cd defender-device-control-unmanaged
Import-Module .\src\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1
```

Confirm 6 cmdlets are exposed:

```powershell
Get-Command -Module DefenderDeviceControlUnmanaged
```

Expected: `Set-DefenderDcPolicy`, `Get-DefenderDcPolicy`,
`Test-DefenderDcPolicy`, `Test-DefenderDcPolicyXml`,
`Invoke-DefenderDcOnboarding`, `Invoke-DefenderDcUsbTest`.

## Step 2: Apply Audit mode (no blocking yet)

Stage the policy in Audit first. Audit logs every event Enforce would
have blocked but does not block anything. It is the safe way to
confirm the engine activated and your rules match the device classes
you intend.

Dry-run first:

```powershell
Set-DefenderDcPolicy -Mode Audit -WhatIf
```

You'll see 5 planned registry writes under
`HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\`. No changes are
made.

Apply:

```powershell
Set-DefenderDcPolicy -Mode Audit
```

The cmdlet validates the policy XMLs through `MpCmdRun.exe`, writes
the 5 values (with `Features\DeviceControlEnabled=1` last so the
master toggle only flips after all policy paths are in place), runs
`gpupdate /force`, and reports the resulting `DeviceControlState`.
Expected last line:

```
[OK] Audit policy applied. DeviceControlState=Audit
```

If you see `DeviceControlState=Disabled` instead, the registry was
written correctly but the engine has not activated -- this is the
MDE attach gate failing. See
[MDE attach gate](concepts/mde-attach-gate.md).

## Step 3: Switch to Enforce

Confirm Audit is genuinely active first:

```powershell
Test-DefenderDcPolicy -ExpectMode Audit
```

Every check should print `[PASS]`. The cmdlet exits non-zero if any
check fails. Once Audit is confirmed, flip to Enforce:

```powershell
Set-DefenderDcPolicy -Mode Enforce
```

Same five registry writes, same `gpupdate`. The only difference is
the rules XML registered: `PolicyRules.Enforce.xml` (entries marked
`Deny`) instead of `PolicyRules.Audit.xml` (entries marked
`AuditAllowed`). Expected last line:

```
[OK] Enforce policy applied. DeviceControlState=Enforce
```

## Step 4: Verify

Static check (registry + engine state):

```powershell
Test-DefenderDcPolicy -ExpectMode Enforce
```

Every line should print `[PASS]`; exit code 0 means the policy is
correctly applied. This is suitable for CI / scripted verification.

Dynamic check (real USB stick on the box):

1. Unplug the stick if it's already mounted (existing handles keep
   the pre-Enforce policy until they close).
2. Plug it back in.
3. Try a write:

```powershell
"test" | Set-Content E:\ddcu-verify.txt
```

Expected: `UnauthorizedAccessException: The media is write protected.`
Also surfaces as a "Write protected" toast from Windows Security.

4. Try a read:

```powershell
Get-ChildItem E:\
```

Expected: succeeds. Read is still allowed.

For a ticketable transcript of the full apply-write-read-restore
cycle, use the wrapper:

```powershell
Invoke-DefenderDcUsbTest -Drive E:
```

## Rollback

To drop back to Audit (keeps the policy installed, lets writes
through):

```powershell
Set-DefenderDcPolicy -Mode Audit
```

To remove the policy entirely (clears all 5 registry values):

```powershell
Set-DefenderDcPolicy -Mode Off
```

The engine may report `DeviceControlState=Enforce` for up to two
minutes after `-Mode Off` while it processes the removal. This is
normal -- see [engine state stickiness](troubleshooting/kb/004-engine-state-stickiness.md)
if it persists beyond that window.

## Where to go next

- Extending to additional device classes (printers, Bluetooth, etc.):
  [Extend device categories](howto/extend-device-categories.md).
- Validating a custom XML before deploy:
  [Validate custom XML](howto/validate-custom-xml.md).
- Full cmdlet reference:
  [Set-DefenderDcPolicy](reference/cmdlets/Set-DefenderDcPolicy.md).
- Why the policy XML format has its constraints (no BOM, no
  `<?xml?>`, Options bitmask 0-3): [Policy XML format](concepts/policy-xml-format.md).

If something doesn't match the expected output above, jump to the
[Troubleshooting symptom ladder](troubleshooting/index.md).
