# Install

Get the module onto the target machine using whichever path matches your
environment.

## Prerequisites

Before installing, confirm all four conditions on the target machine from
an elevated PowerShell window:

- **Windows 11 or Windows 10 Enterprise** (build 22621 or later for
  Windows 11). The Defender Device Control engine is only available on
  Enterprise editions.
- **PowerShell 5.1 or later.** PowerShell 5.1 ships with every supported
  Windows 11 build. PowerShell 7.x also works.
- **MDE attach.** The machine must be onboarded to Microsoft Defender for
  Endpoint (Plan 1, Plan 2, or Defender for Business). If it is not yet
  onboarded, see [Onboard to MDE](../howto/onboard-to-mde.md) and come
  back here when `Get-Service Sense` reports `Running`.
- **Local administrator.** Registry writes under `HKLM:\` require an
  elevated session. Right-click PowerShell and choose "Run as
  administrator" before proceeding.

## Option A: Install from the PowerShell Gallery (preferred)

This path requires outbound HTTPS to `powershellgallery.com`.

```powershell
Install-Module -Name DefenderDeviceControlUnmanaged -Scope CurrentUser
Import-Module DefenderDeviceControlUnmanaged
```

`-Scope CurrentUser` avoids an additional elevation prompt for the module
installation itself. The cmdlets still require elevation when they write
to the registry.

To pin a specific version:

```powershell
Install-Module -Name DefenderDeviceControlUnmanaged -RequiredVersion 1.0.0 -Scope CurrentUser
```

## Option B: Clone the repo and import locally (no Gallery egress)

Use this path on air-gapped or Gallery-blocked machines.

```powershell
git clone https://github.com/LukeEvansTech/defender-device-control-unmanaged.git
cd defender-device-control-unmanaged
Import-Module .\src\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1
```

The module loads from the `src\` tree directly. All 6 cmdlets are
available immediately; no build step is required for local use.

## Smoke test

After either installation path, verify the module surface:

```powershell
Get-Command -Module DefenderDeviceControlUnmanaged
```

Expected output -- exactly 6 cmdlets:

```
CommandType  Name                          Version  Source
-----------  ----                          -------  ------
Function     Get-DefenderDcPolicy          1.0.0    DefenderDeviceControlUnmanaged
Function     Invoke-DefenderDcOnboarding   1.0.0    DefenderDeviceControlUnmanaged
Function     Invoke-DefenderDcUsbTest      1.0.0    DefenderDeviceControlUnmanaged
Function     Set-DefenderDcPolicy          1.0.0    DefenderDeviceControlUnmanaged
Function     Test-DefenderDcPolicy         1.0.0    DefenderDeviceControlUnmanaged
Function     Test-DefenderDcPolicyXml      1.0.0    DefenderDeviceControlUnmanaged
```

If fewer than 6 cmdlets appear, the module did not load correctly. Re-run
`Import-Module` with the `-Verbose` flag to see which file failed to load.

## Next steps

Proceed to [Audit mode](audit-mode.md) to stage the policy safely before
you enforce it.
