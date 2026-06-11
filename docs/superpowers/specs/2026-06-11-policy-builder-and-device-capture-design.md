# Design: Parameter-Driven Policy Builder + Device Capture

Date: 2026-06-11
Status: Approved (brainstorming session)

## Goal

Let operators craft custom Defender Device Control policies from simple
PowerShell parameters instead of hand-editing XML, and capture the hardware
identifiers of physical devices so approved devices can be exempted from
restrictions. Two new public cmdlets plus a small pipeline enhancement to
`Set-DefenderDcPolicy`.

End-to-end flow:

```powershell
# 1. Capture approved devices (plug them in one by one)
Get-DefenderDcDevice -Watch -OutFile .\approved.json

# 2. Craft the policy
New-DefenderDcPolicy -Usb ReadOnly,DenyExecute -Wpd ReadOnly `
    -AllowDeviceFile .\approved.json -OutputPath .\policy\

# 3. Apply (file paths or pipeline)
New-DefenderDcPolicy -Usb ReadOnly -OutputPath .\policy\ |
    Set-DefenderDcPolicy -Mode Audit
```

## Scope

In scope (v1):

- Device classes: USB removable storage (`RemovableMediaDevices`), WPD/MTP
  (`WpdDevices`), optical (`CdRomDevices`) — the classes the module already
  covers, now individually tunable.
- Restriction flags per class, hardware-ID exceptions, live device capture.

Out of scope (future): Bluetooth (no native PrimaryId on Windows; needs
HardwareId-based matching research), printers (`PrinterDevices`), network/VPN
conditions, file-evidence options, removable-media allowlist-only postures.

## Cmdlet 1: `New-DefenderDcPolicy`

Pure XML generation. No registry access, no elevation, runs on any platform
(including CI). Validation of the generated XML stays with the existing
`Test-DefenderDcPolicyXml` / `Set-DefenderDcPolicy` MpCmdRun preflight.

### Parameters

| Parameter | Type | Notes |
|---|---|---|
| `-Usb` | restriction flags | Removable storage (`RemovableMediaDevices`) |
| `-Wpd` | restriction flags | Phones/cameras (`WpdDevices`) |
| `-Optical` | restriction flags | CD/DVD (`CdRomDevices`) |
| `-AllowHardwareId` | `string[]` | Inline hardware-ID strings exempted from all restrictions |
| `-AllowDevice` | device objects, `ValueFromPipeline` | Objects from `Get-DefenderDcDevice` |
| `-AllowDeviceFile` | `string` (path) | JSON file written by `Get-DefenderDcDevice -OutFile` |
| `-OutputPath` | `string` (directory) | Defaults to the current directory |
| `-PolicyName` | `string` | Optional label woven into rule names; default `Custom policy` |

At least one class parameter (`-Usb`, `-Wpd`, `-Optical`) is required.
`-AllowHardwareId`, `-AllowDevice`, and `-AllowDeviceFile` are independent,
combinable inputs that merge into a single approved-devices group (deduped).
All exception parameters are optional — the minimal call is e.g.
`New-DefenderDcPolicy -Usb ReadOnly`.

### Restriction flags

Values per class parameter (comma-separated, validated):

| Flag | Meaning | Valid combos |
|---|---|---|
| `ReadOnly` | Deny write | May combine with `DenyExecute` |
| `DenyExecute` | Deny execute | May combine with `ReadOnly` |
| `Block` | Deny read+write+execute | Exclusive |
| `Allow` | No restriction; audit visibility only | Exclusive |

Flag-to-AccessMask mapping uses the real Device Control masks, matching the
shipped starter XMLs:

| Class | Write | Execute | Read | `Block` mask |
|---|---|---|---|---|
| Usb (disk-style) | 2 | 4 | 1 | 7 |
| Optical (disk-style) | 2 | 4 | 1 | 7 |
| Wpd | 16 | 32 | 8 | 56 |

### Output

Writes the same three-file shape the module ships today, so audit-first-then-
enforce stays a one-flag switch at apply time:

- `PolicyGroups.xml` — one `<Group>` per class parameter supplied (PrimaryId
  match), plus one "Approved devices" group when any exception input is given.
- `PolicyRules.Audit.xml` — per restricted class: an `AuditAllowed` entry
  (Options 2) with the combined deny mask. A class set to `Allow` gets an
  `AuditAllowed` entry with its full mask (visibility without restriction).
- `PolicyRules.Enforce.xml` — per restricted class: a `Deny` entry (Options 0)
  plus an `AuditDenied` entry (Options 3), both with the combined mask. A
  class set to `Allow` produces no entries here.

Returns a result object for piping:

```powershell
[pscustomobject]@{
    GroupsXmlPath       = '...\PolicyGroups.xml'
    AuditRulesXmlPath   = '...\PolicyRules.Audit.xml'
    EnforceRulesXmlPath = '...\PolicyRules.Enforce.xml'
}
```

### Approved-devices exceptions

- One group (`Type="Device"`, `MatchType="MatchAny"`) holds all exceptions.
- Every class deny rule references it in `ExcludedIdList`, so approved
  devices are exempt from all class restrictions (full access).
- Descriptor mapping: device objects (pipeline / `-AllowDeviceFile`)
  contribute their `InstancePathId` (serial-specific — approves *that* stick,
  not every stick of that model); raw `-AllowHardwareId` strings are emitted
  as `<HardwareId>` descriptors (model-wide match).

### Deterministic GUIDs

Group/rule/entry IDs are derived (UUIDv5-style: SHA-1 of a fixed namespace
GUID + a stable seed such as `ddcu:rule:usb` or `ddcu:group:approved`) rather
than random. Regenerating the same policy yields byte-identical XML — clean
git diffs and exact golden-file tests. Seeds differ from the shipped starter
XML GUIDs, so a generated policy never collides with the starter policy.

## Cmdlet 2: `Get-DefenderDcDevice`

Windows-only (clear error elsewhere). Read-only PnP queries — no elevation
required.

### Modes

- **Snapshot (default):** enumerates currently-connected devices in the three
  supported classes via CIM (`Win32_PnPEntity` + PnP device properties).
- **`-Watch`:** registers a CIM device-arrival event subscription
  (`__InstanceCreationEvent` on `Win32_PnPEntity`), emits each newly plugged
  device as it arrives, until Ctrl+C or `-Timeout <seconds>`. Event
  subscriptions are cleaned up in `finally`.

### Output object

```powershell
[pscustomobject]@{
    FriendlyName   = 'Kingston DataTraveler 3.0'
    Class          = 'Usb'        # Usb | Wpd | Optical
    InstancePathId = 'USBSTOR\DISK&VEN_KINGSTON&...\E0D55EA574DBF750E97B0A14&0'
    HardwareIds    = @('USBSTOR\DiskKingstonDataTraveler_3.0', ...)
    VidPid         = 'VID_0951&PID_1666'
    SerialNumber   = 'E0D55EA574DBF750E97B0A14'
    CapturedAt     = '2026-06-11T14:03:12Z'
}
```

### `-OutFile`

Appends each captured device to a JSON array file as it arrives (read-modify-
write, deduped by `InstancePathId`), so a watch session interrupted by Ctrl+C
keeps everything captured so far. The file is exactly what
`New-DefenderDcPolicy -AllowDeviceFile` consumes. Direct piping also works:
`Get-DefenderDcDevice -Watch | New-DefenderDcPolicy -Usb ReadOnly`.

## Change to `Set-DefenderDcPolicy`

Accept the builder's result object from the pipeline
(`ValueFromPipelineByPropertyName`):

- `GroupsXmlPath` binds directly to the existing parameter.
- New pipeline-bindable `AuditRulesXmlPath` / `EnforceRulesXmlPath`
  parameters; `-Mode Audit|Enforce` selects which one becomes the effective
  rules path. An explicitly supplied `-RulesXmlPath` always wins.
- No behavior change for existing file-path usage or shipped defaults.

## Error handling

Fail fast with actionable messages:

- Conflicting flags (`Block,ReadOnly`, `Allow,DenyExecute`, etc.) — rejected
  at parameter validation.
- No class parameter supplied — error ("specify at least one of -Usb, -Wpd,
  -Optical").
- `-AllowDeviceFile` missing, unreadable, or not an array of device objects
  with `InstancePathId` — error naming the file and the problem.
- Unwritable `-OutputPath` — error before any file is partially written.
- `Get-DefenderDcDevice` on non-Windows / no CIM — clear "Windows required".

## Testing

Pester unit tests mirroring the existing one-file-per-function layout:

- **Builder:** golden-file XML assertions (deterministic GUIDs make these
  byte-exact); flag-to-mask matrix; exception merging/dedup across the three
  inputs; parameter-validation failures.
- **Capture:** mocked CIM for snapshot and watch paths; JSON append/dedup;
  class detection (USBSTOR/WPD/CDROM).
- **Set- pipeline:** property binding and Mode-based rules-path selection.
- CI already runs Pester on PowerShell 5.1 and 7.x — new code must pass both.

## Documentation

- Docs site: a "Crafting custom policies" page and an end-to-end
  capture → craft → apply walkthrough.
- New `examples/` scripts (e.g. `Capture-And-Allow.ps1`,
  `Craft-Custom-Policy.ps1`).
- Comment-based help on both new cmdlets matching the existing house style.
