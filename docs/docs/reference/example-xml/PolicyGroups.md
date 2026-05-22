# PolicyGroups.xml (starter)

This is the starter groups file shipped with the module. It is used by default when you
run `Set-DefenderDcPolicy -Mode Audit` or `Set-DefenderDcPolicy -Mode Enforce` without
supplying `-GroupsXmlPath`. It is not the authoritative definition of what you must
deploy -- it is a reasonable starting point for a three-class read-only USB policy.

Fork this file to your own working location before modifying it. See
[Extend device categories](../../howto/extend-device-categories.md) for the full
walkthrough.

---

## Full content

```xml
<Groups>
  <Group Id="{18c18655-7803-4235-a811-3da676a1f197}" Type="Device">
    <Name>Removable storage (USB sticks, external HDDs)</Name>
    <MatchType>MatchAny</MatchType>
    <DescriptorIdList>
      <PrimaryId>RemovableMediaDevices</PrimaryId>
    </DescriptorIdList>
  </Group>
  <Group Id="{b9854cf9-b7e3-4155-b0ec-5031d44657b3}" Type="Device">
    <Name>WPD / MTP devices (phones, cameras)</Name>
    <MatchType>MatchAny</MatchType>
    <DescriptorIdList>
      <PrimaryId>WpdDevices</PrimaryId>
    </DescriptorIdList>
  </Group>
  <Group Id="{c145b8d2-2799-469b-8014-927e7dd9babf}" Type="Device">
    <Name>Optical drives</Name>
    <MatchType>MatchAny</MatchType>
    <DescriptorIdList>
      <PrimaryId>CdRomDevices</PrimaryId>
    </DescriptorIdList>
  </Group>
</Groups>
```

---

## Annotated walkthrough

### Root element

`<Groups>` is the required root element for a device-group policy file. The engine
rejects any file whose root element is not exactly `<Groups>` (checked by layer 1 of
`Test-DefenderDcPolicyXml -Kind Groups`).

---

### Group 1 -- Removable storage

```xml
<Group Id="{18c18655-7803-4235-a811-3da676a1f197}" Type="Device">
  <Name>Removable storage (USB sticks, external HDDs)</Name>
  <MatchType>MatchAny</MatchType>
  <DescriptorIdList>
    <PrimaryId>RemovableMediaDevices</PrimaryId>
  </DescriptorIdList>
</Group>
```

- **Id**: A unique GUID in curly braces. The rules file references this GUID in
  `<GroupId>`. Do not reuse GUIDs across groups.
- **Type="Device"**: The only type in use for device-class policies. Left as a fixed
  attribute.
- **Name**: Human-readable label. Not parsed by the engine -- purely for operator
  readability.
- **MatchType=MatchAny**: The group matches a device if any of the descriptors in
  `<DescriptorIdList>` match. With a single descriptor this is equivalent to an exact
  match.
- **PrimaryId=RemovableMediaDevices**: The Defender Device Control primary descriptor
  for the removable disk bus class. This covers USB flash drives, USB-attached hard
  drives, and SD card readers. It does not include MTP/PTP devices (phones, cameras),
  which have their own primary descriptor.

---

### Group 2 -- WPD / MTP devices

```xml
<Group Id="{b9854cf9-b7e3-4155-b0ec-5031d44657b3}" Type="Device">
  <Name>WPD / MTP devices (phones, cameras)</Name>
  <MatchType>MatchAny</MatchType>
  <DescriptorIdList>
    <PrimaryId>WpdDevices</PrimaryId>
  </DescriptorIdList>
</Group>
```

- **PrimaryId=WpdDevices**: Matches devices that communicate over the Windows Portable
  Devices (WPD) / Media Transfer Protocol (MTP) stack. This includes smartphones,
  digital cameras, and media players. These devices do not appear as drive letters;
  they are accessed via the WPD API or Windows Explorer's "portable device" node.
- The `AccessMask` on the corresponding rule uses values 48 (MTP Send + File Execute)
  rather than the 6 (Write + Execute) used for removable storage, because the WPD
  access model differs from the block-device model.

---

### Group 3 -- Optical drives

```xml
<Group Id="{c145b8d2-2799-469b-8014-927e7dd9babf}" Type="Device">
  <Name>Optical drives</Name>
  <MatchType>MatchAny</MatchType>
  <DescriptorIdList>
    <PrimaryId>CdRomDevices</PrimaryId>
  </DescriptorIdList>
</Group>
```

- **PrimaryId=CdRomDevices**: Matches CD, DVD, and Blu-ray optical drives. On devices
  without a built-in or attached optical drive this group matches nothing and the
  corresponding rule is inert. Including it does not cause errors on a drive-less device.

---

## Extending the group file

Each `<Group>` can contain multiple `<PrimaryId>` children, multiple `<InstancePathId>`
children, or hardware-ID-based descriptors such as `<VID_PID>`. All descriptors inside
the group are combined with the logic specified by `MatchType`. `MatchAny` means OR;
`MatchAll` means AND.

To add a new device class, append a new `<Group>` with a fresh GUID and add a matching
`<PolicyRule>` to the rules file. See
[Extend device categories](../../howto/extend-device-categories.md) for the step-by-step
process and [policy-xml-format](../../concepts/policy-xml-format.md) for the full schema
reference.
