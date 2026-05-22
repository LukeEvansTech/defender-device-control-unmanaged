# Audit vs Enforce

Audit mode and Enforce mode use the same five registry values and the
same Groups XML. The only difference is in the Rules XML: Audit registers
`PolicyRules.Audit.xml` and Enforce registers `PolicyRules.Enforce.xml`.
The registry surface is identical in both modes; the behaviour diverges
entirely because of what is inside those files.

![Audit vs Enforce comparison](../media/diagrams/D4-audit-vs-enforce.svg)

## Same 5 registry writes

Both modes write the same five values described in
[Registry surface](registry-surface.md). The path stored in the
`PolicyRules` REG_SZ value is the only item that changes:

- **Audit:** `...\policy\PolicyRules.Audit.xml`
- **Enforce:** `...\policy\PolicyRules.Enforce.xml`

Everything else -- `DeviceControlEnabled`, `DefaultEnforcement`,
`SecuredDevicesConfiguration`, and the `PolicyGroups` path -- is the
same in both modes.

## Different XML body: Entry Type

Inside the Rules XML, each entry has a `Type` attribute that determines
the engine action:

**Audit mode entry (from `PolicyRules.Audit.xml`):**

```xml
<Entry Id="{...}">
  <Type>AuditAllowed</Type>
  <AccessMask>6</AccessMask>
  <Options>2</Options>
</Entry>
```

**Enforce mode entry (from `PolicyRules.Enforce.xml`):**

```xml
<Entry Id="{...}">
  <Type>Deny</Type>
  <AccessMask>6</AccessMask>
  <Options>0</Options>
</Entry>
```

`AuditAllowed` logs the access and allows it. `Deny` blocks it.

## AccessMask values

The access mask is a bitmask of the operations being covered:

| Value | Operations | Applies to |
|-------|------------|------------|
| `6` | Write + Execute | Removable disks (USB sticks) |
| `2` | Write | Optical media (CD/DVD) |
| `48` | MTP write + file execute | WPD devices (cameras, phones) |

For removable disks, the shipped policy uses mask `6` to deny both
writing to the disk and executing files from it. Optical media uses `2`
because optical drives do not have a meaningful execute path in this
context. WPD uses `48` for MTP-level write and file execution via the
WPD protocol.

## Options bitmask

`<Options>` is a 2-bit bitmask with values 0 through 3:

| Value | Meaning |
|-------|---------|
| `0` | No audit, no notification (used with `Deny`) |
| `2` | AuditAllowed event sent to Defender XDR |
| `3` | AuditDenied event sent to Defender XDR (used alongside `Deny` for deny logging) |

The Enforce rules XML can include two entries per rule: a `Deny` entry
with `Options=0` to block, and an `AuditDenied` entry with `Options=3`
to log the denial to Defender XDR. The shipped example uses this
pattern so every Enforce denial also produces a telemetry event.

## Practical recommendation

Apply Audit for at least a week before switching to Enforce on any
machine you have not tested before. The Advanced Hunting query
`DeviceEvents | where ActionType == 'RemovableStoragePolicyTriggered'`
in Defender XDR shows you exactly which device classes and access
patterns are being matched. Reviewing that output before enforcing
confirms the rules are covering the right things without surprises.
