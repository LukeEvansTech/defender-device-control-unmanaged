# Craft custom policies

Build a Device Control policy from parameters instead of hand-editing XML,
with specific approved devices exempted.

## 1. Capture the devices you want to approve

No elevation needed — these are read-only PnP queries.

```powershell
Get-DefenderDcDevice -Watch -OutFile .\approved.json
```

Plug each approved device in; every arrival prints its identifiers
(`InstancePathId`, `HardwareIds`, VID/PID, serial) and appends to
`approved.json`. ++ctrl+c++ when done. Without `-Watch` you get a snapshot of
currently-connected devices instead.

## 2. Craft the policy

```powershell
New-DefenderDcPolicy -Usb ReadOnly,DenyExecute -Wpd ReadOnly -Optical Block `
    -AllowDeviceFile .\approved.json -OutputPath .\policy\
```

Restriction flags per class (`-Usb`, `-Wpd`, `-Optical`):

| Flag          | Effect                                            |
| ------------- | ------------------------------------------------- |
| `ReadOnly`    | Deny write                                        |
| `DenyExecute` | Deny execute (combinable with `ReadOnly`)         |
| `Block`       | Deny read+write+execute (exclusive)               |
| `Allow`       | No restriction, audit visibility only (exclusive) |

This writes the same three-file shape the module ships — `PolicyGroups.xml`,
`PolicyRules.Audit.xml`, `PolicyRules.Enforce.xml` — so switching from audit
to enforce later is a one-flag change. Approved devices land in an
"Approved devices" group referenced from every rule's `ExcludedIdList`:
they keep full access.

GUIDs are deterministic: regenerate the same policy and the XML is
byte-identical (clean Git diffs).

## 3. Apply it

```powershell
# pipeline (the -Mode flag picks the audit or enforce rules file)
New-DefenderDcPolicy -Usb ReadOnly -OutputPath .\policy\ |
    Set-DefenderDcPolicy -Mode Audit

# or explicit paths
Set-DefenderDcPolicy -Mode Enforce -GroupsXmlPath .\policy\PolicyGroups.xml `
    -RulesXmlPath .\policy\PolicyRules.Enforce.xml
```

Validate first without applying: `Test-DefenderDcPolicyXml -Path .\policy\PolicyGroups.xml -Kind Groups`.

## Matching semantics

- Devices captured by `Get-DefenderDcDevice` are exempted by
  **InstancePathId** — serial-specific, approves _that_ stick.
- Strings passed to `-AllowHardwareId` become **HardwareId** descriptors —
  model-wide, approves every device of that model.
