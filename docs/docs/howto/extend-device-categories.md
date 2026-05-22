# Extend device categories

The starter policy XMLs cover three device classes: removable storage (USB sticks and
external HDDs), WPD/MTP devices (phones and cameras), and optical drives. You may need
to target a different device class, apply a different access mask, or carve out a
specific device by hardware ID. This page shows the full workflow for extending the
shipped XML pair with a new group and rule.

![Apply lifecycle](../media/diagrams/D5-apply-lifecycle.svg)

---

## Step 1: Copy the starter XML to a working location

The shipped XMLs live inside the module. Copy them to a location you own before editing.

```powershell
$src = (Get-Module DefenderDeviceControlUnmanaged -ListAvailable | Select-Object -First 1).ModuleBase
Copy-Item "$src\policy\PolicyGroups.xml"      C:\MyPolicy\Groups.xml
Copy-Item "$src\policy\PolicyRules.Enforce.xml" C:\MyPolicy\Rules.xml
```

If you want an Audit rule set as the base, copy `PolicyRules.Audit.xml` instead.

---

## Step 2: Add a new `<Group>` to Groups.xml

Open `C:\MyPolicy\Groups.xml` in an editor. The existing groups use `MatchType=MatchAny`
and a single `<PrimaryId>` child. Add a second group below the three existing ones.

The recognised `PrimaryId` values are:

| Value | Device class |
|---|---|
| `RemovableMediaDevices` | USB sticks, external HDDs |
| `WpdDevices` | MTP/PTP devices (phones, cameras) |
| `CdRomDevices` | Optical drives |
| `PrinterDevices` | Printers (USB and network-attached) |

Example -- add a printer group:

```xml
<Group Id="{a1b2c3d4-0000-0000-0000-000000000001}" Type="Device">
  <Name>Printers</Name>
  <MatchType>MatchAny</MatchType>
  <DescriptorIdList>
    <PrimaryId>PrinterDevices</PrimaryId>
  </DescriptorIdList>
</Group>
```

Choose a new GUID for `Id`. You can generate one with `[System.Guid]::NewGuid()` in
PowerShell. The GUID must be wrapped in curly braces and must not clash with any
existing group GUID.

To match multiple descriptors in one group -- for example a vendor-specific device ID
alongside a PrimaryId -- add additional child elements inside `<DescriptorIdList>`.
Each child is evaluated as an OR when `MatchType=MatchAny`.

---

## Step 3: Add a matching `<PolicyRule>` to Rules.xml

Open `C:\MyPolicy\Rules.xml`. Add a rule that references the new group GUID via
`<IncludedIdList>`. Use the same GUID you assigned in Step 2.

```xml
<PolicyRule Id="{a1b2c3d4-0000-0000-0000-000000000002}">
  <Name>Deny write on printers</Name>
  <IncludedIdList>
    <GroupId>{a1b2c3d4-0000-0000-0000-000000000001}</GroupId>
  </IncludedIdList>
  <ExcludedIdList></ExcludedIdList>
  <Entry Id="{a1b2c3d4-0000-0000-0000-000000000003}">
    <Type>Deny</Type>
    <Options>0</Options>
    <AccessMask>64</AccessMask>
  </Entry>
  <Entry Id="{a1b2c3d4-0000-0000-0000-000000000004}">
    <Type>AuditDenied</Type>
    <Options>3</Options>
    <AccessMask>64</AccessMask>
  </Entry>
</PolicyRule>
```

Common `AccessMask` values:

| Decimal | Meaning |
|---|---|
| 1 | Read |
| 2 | Write |
| 4 | Execute |
| 6 | Write + Execute (2+4) |
| 48 | MTP Send/Receive + File Execute (WPD) |
| 64 | Print |

The Deny entry blocks the access. The paired `AuditDenied` entry (Options=3) emits the
blocked-event telemetry. Omitting `AuditDenied` means the deny still happens but no
event appears in Defender XDR Advanced Hunting.

---

## Step 4: Validate both files

Validate before writing anything to the registry. See
[Validate custom XML](validate-custom-xml.md) for full detail on what each layer checks.

```powershell
Test-DefenderDcPolicyXml -Path C:\MyPolicy\Groups.xml -Kind Groups
Test-DefenderDcPolicyXml -Path C:\MyPolicy\Rules.xml  -Kind Rules
```

Both must return `True`. If either returns `False`, the `Write-Error` output tells you
exactly which constraint failed.

---

## Step 5: Deploy

```powershell
Set-DefenderDcPolicy -Mode Enforce `
    -GroupsXmlPath C:\MyPolicy\Groups.xml `
    -RulesXmlPath  C:\MyPolicy\Rules.xml
```

The cmdlet re-validates, removes any prior policy state, writes the 5 registry values,
runs `gpupdate /force`, and nudges the engine with `Update-MpSignature`. See
[Set-DefenderDcPolicy](../reference/cmdlets/Set-DefenderDcPolicy.md) for all parameters.

![Editor side-by-side](../media/screenshots/S5-xml-editor-diff.png)

---

## Step 6: Verify

```powershell
Test-DefenderDcPolicy -ExpectMode Enforce
```

All static checks should report PASS. The engine's `DeviceControlState` must not be
`Disabled` and `DeviceControlPoliciesLastUpdated` must be a date after the epoch sentinel.

---

## Recording

![Custom XML cycle](../media/recordings/T2-custom-xml.gif)

---

## Related

- [Validate custom XML](validate-custom-xml.md)
- [policy-xml-format concept](../concepts/policy-xml-format.md)
- [Set-DefenderDcPolicy reference](../reference/cmdlets/Set-DefenderDcPolicy.md)
