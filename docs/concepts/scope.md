# Scope

Understanding what this module does not do is as important as knowing
what it does. The items below are deliberate design decisions, not
missing features.

## Not a fleet rollout tool

This module applies policy to one machine at a time. `Set-DefenderDcPolicy`
writes to the local registry of the machine where it runs. There is no
remote-target parameter, no bulk-apply, and no configuration baseline
export.

For fleet rollout, use the tools designed for it: Intune Device
Configuration Profiles, domain Group Policy through GPMC, or
Configuration Manager. Those tools push the same underlying registry
surface this module writes -- they just do it at scale. This module is
the path for individual machines that sit outside those management
planes.

## Not an MDE substitute

This module configures the Defender Device Control policy layer. It does
not replace or substitute for the Defender for Endpoint agent. The MDE
attach gate described in [MDE attach gate](mde-attach-gate.md) is not a
limitation of the module -- it is a feature of the engine. Without an
active MDE subscription and a completed onboarding, `DeviceControlState`
stays `Disabled` regardless of what the registry contains.

If the machine cannot be onboarded to MDE, Defender Device Control is
not the right mechanism. The Microsoft in-box Removable Storage Access
(RSA) GPO policy is an alternative that works without MDE but provides
coarser control and no audit mode.

## No per-user SID carve-outs in v1

The shipped policy applies uniformly to all users on the machine. There
is no mechanism in v1 to exempt a specific user account (for example,
a local service account that must write to USB). Per-user SID
exemptions are a Defender DC XML capability that this module does not
expose in its v1 cmdlet surface.

If you need per-user carve-outs, you can supply a custom Groups and
Rules XML via `-GroupsXmlPath` and `-RulesXmlPath` on `Set-DefenderDcPolicy`.
See [Extend device categories](../howto/extend-device-categories.md) and
the [Defender DC schema reference](https://learn.microsoft.com/en-us/defender-endpoint/device-control-overview)
for the XML elements involved.

## No BitLocker-to-Go exemption

Encrypted removable drives (BitLocker-to-Go) are still classified as
removable storage. They are matched by the `RemovableMediaDevices` class
in `SecuredDevicesConfiguration` and subject to the same write and
execute deny as any other USB stick. There is no carve-out for
encryption status in v1.

## WPD execute semantics are weaker than disk execute

The execute-deny entry for WPD devices (cameras, phones connected via
MTP) covers the MTP file-execution path and uses `AccessMask=48`. The
semantics are weaker than the `AccessMask=6` execute-deny on removable
disks, which covers direct block-device execution. The WPD entry is
included for defence-in-depth; it should not be relied upon as the
primary control for preventing execution from a phone or camera.

## Optical write-deny is inert without a burner

The `CdRomDevices` entry in `SecuredDevicesConfiguration` and the
corresponding `AccessMask=2` write-deny rule only fire if a CD or DVD
write-capable drive exists on the machine. On hardware without an optical
burner -- which is most modern laptops and workstations -- this entry is
registered but never triggered. It is included because some environments
have optical drives present.

## Extending beyond v1 defaults

If your environment requires device categories, access masks, or rule
structures that the shipped XML does not cover, the module supports
deploying custom XML. See
[Extend device categories](../howto/extend-device-categories.md) for
the workflow.
