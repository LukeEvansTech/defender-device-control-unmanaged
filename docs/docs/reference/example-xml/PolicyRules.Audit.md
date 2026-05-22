# PolicyRules.Audit.xml (starter)

This is the rule set applied when you run `Set-DefenderDcPolicy -Mode Audit`. In Audit
mode the engine logs access candidates that would have been denied under Enforce mode
but does not actually block them. Users experience no disruption; telemetry accumulates
in Defender XDR Advanced Hunting for review.

The companion enforce file is documented at
[PolicyRules.Enforce.xml](PolicyRules.Enforce.md).

---

## Full content

```xml
<PolicyRules>
  <PolicyRule Id="{77d21842-eba0-44a7-a46a-1c0291b087e0}">
    <Name>Audit write+execute on removable storage</Name>
    <IncludedIdList>
      <GroupId>{18c18655-7803-4235-a811-3da676a1f197}</GroupId>
    </IncludedIdList>
    <ExcludedIdList></ExcludedIdList>
    <Entry Id="{88274f5f-1e0f-4d1f-b239-b8b4a1b2602e}">
      <Type>AuditAllowed</Type>
      <Options>2</Options>
      <AccessMask>6</AccessMask>
    </Entry>
  </PolicyRule>
  <PolicyRule Id="{d1a03385-6742-4f39-b05f-7f7f5c5bee1e}">
    <Name>Audit write+execute on WPD</Name>
    <IncludedIdList>
      <GroupId>{b9854cf9-b7e3-4155-b0ec-5031d44657b3}</GroupId>
    </IncludedIdList>
    <ExcludedIdList></ExcludedIdList>
    <Entry Id="{e392a0e6-269c-4037-b125-68a8fa78ada4}">
      <Type>AuditAllowed</Type>
      <Options>2</Options>
      <AccessMask>48</AccessMask>
    </Entry>
  </PolicyRule>
  <PolicyRule Id="{f3c3878f-3133-4b5a-83e8-4b4b79c35591}">
    <Name>Audit write on optical</Name>
    <IncludedIdList>
      <GroupId>{c145b8d2-2799-469b-8014-927e7dd9babf}</GroupId>
    </IncludedIdList>
    <ExcludedIdList></ExcludedIdList>
    <Entry Id="{6996b8cd-5bfc-4143-b67f-133cc784d8c0}">
      <Type>AuditAllowed</Type>
      <Options>2</Options>
      <AccessMask>2</AccessMask>
    </Entry>
  </PolicyRule>
</PolicyRules>
```

---

## Annotated walkthrough

### Root element

`<PolicyRules>` is the required root element for a rules file. The engine rejects any
file whose root element is not exactly `<PolicyRules>` (checked by layer 1 of
`Test-DefenderDcPolicyXml -Kind Rules`).

---

### Rule 1 -- Removable storage

```xml
<PolicyRule Id="{77d21842-eba0-44a7-a46a-1c0291b087e0}">
  <Name>Audit write+execute on removable storage</Name>
  <IncludedIdList>
    <GroupId>{18c18655-7803-4235-a811-3da676a1f197}</GroupId>
  </IncludedIdList>
  <ExcludedIdList></ExcludedIdList>
  <Entry Id="{88274f5f-1e0f-4d1f-b239-b8b4a1b2602e}">
    <Type>AuditAllowed</Type>
    <Options>2</Options>
    <AccessMask>6</AccessMask>
  </Entry>
</PolicyRule>
```

- **IncludedIdList / GroupId**: References the GUID of the "Removable storage" group in
  `PolicyGroups.xml`. The rule applies to every device that matches that group.
- **ExcludedIdList**: Empty here. Populate with `<GroupId>` entries to carve out
  specific sub-groups (for example, a trusted-device group identified by hardware ID).
- **Type=AuditAllowed**: The entry logs the access but does not block it. This is the
  Audit-mode entry type. Compare with `Deny` and `AuditDenied` in the Enforce file.
- **Options=2**: The Options bitmask controls notification and audit behaviour. Value 2
  means "emit a silent audit event to Defender XDR" with no on-screen notification to
  the user.

  | Value | Meaning |
  |---|---|
  | 0 | No event, no notification |
  | 1 | User notification toast only |
  | 2 | Silent audit event (Defender XDR) |
  | 3 | Audit event + user notification |

- **AccessMask=6**: Bitmask of the access types being audited. 6 = Write (2) + Execute
  (4). Read access (1) is not included -- users can always read from removable storage
  under this policy.

---

### Rule 2 -- WPD / MTP devices

```xml
<Entry Id="{e392a0e6-269c-4037-b125-68a8fa78ada4}">
  <Type>AuditAllowed</Type>
  <Options>2</Options>
  <AccessMask>48</AccessMask>
</Entry>
```

- **AccessMask=48**: WPD devices use a different access model from block devices.
  48 = MTP Send (16) + MTP Receive (receive-execute, 32). These are the two access
  types that correspond to writing data to or executing files from a phone or camera
  over MTP.

---

### Rule 3 -- Optical drives

```xml
<Entry Id="{6996b8cd-5bfc-4143-b67f-133cc784d8c0}">
  <Type>AuditAllowed</Type>
  <Options>2</Options>
  <AccessMask>2</AccessMask>
</Entry>
```

- **AccessMask=2**: Write only. Optical drives do not support Execute in the same way
  removable storage does; only write access is relevant for disc-burning scenarios.

---

## Relationship to the Enforce file

The Audit file uses a single `AuditAllowed` entry per rule. The Enforce file replaces
this with a paired `Deny` + `AuditDenied` entry. The `PolicyRule` and `GroupId` GUIDs
are the same across both files -- the mode of operation changes the entry types, not the
group assignments.

See [audit-vs-enforce](../../concepts/audit-vs-enforce.md) for a conceptual comparison
and [PolicyRules.Enforce.xml](PolicyRules.Enforce.md) for the annotated enforce file.
