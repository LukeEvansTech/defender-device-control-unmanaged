# Why this module exists

Microsoft Defender Device Control is a powerful USB-control feature available to any Windows 11 device with a Microsoft Defender for Endpoint (MDE) attach - Plan 1, Plan 2, or Defender for Business. The catch: Microsoft's documentation assumes one of three deployment methods, all of which require centralised management:

1. **Intune Configuration Service Provider (CSP)** - requires Intune.
2. **Domain Group Policy via GPMC** - requires Active Directory + GPMC + domain join.
3. **Configuration Manager** - requires SCCM/MECM.

On a standalone unmanaged Windows 11 device, none of these apply. You have an MDE license, you have the Defender engine, you have everything you need *except* the deployment path.

## The missing piece

Defender Device Control reads policy from a specific local Group Policy registry surface - five values under `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control` - which is exactly what GPMC writes when it pushes the policy from a domain controller. This surface is documented (in the sense that the `WindowsDefender.admx` schema is public), but never explained as a deployable path for unmanaged endpoints.

This module writes that surface directly, locally, with one cmdlet. The engine consumes it identically to a GPMC-pushed policy.

## What this is not

- **Not a way to use Defender Device Control without MDE.** The engine still requires an MDE attach to activate. See [MDE attach gate](concepts/mde-attach-gate.md).
- **Not a Microsoft product.** This is an unaffiliated open-source module that drives a documented Microsoft feature.
- **Not a fleet rollout tool.** Each box runs it locally. For fleet rollout, use Intune or GPMC and skip this module.

## What changes when you use this

You get to deploy Defender Device Control on a single unmanaged box in 60 seconds, without standing up Intune, joining a domain, or maintaining infrastructure. The policy itself is identical to what a managed device would receive - same registry shape, same XML format, same engine evaluation - just authored locally and applied locally.

That's it. The module is a thin, well-tested bridge across a narrow but real gap in Microsoft's deployment options.
