# PolicyRules.Enforce.xml (starter)

This is the rule set applied when you run `Set-DefenderDcPolicy -Mode Enforce`. In
Enforce mode the engine actively blocks the access types listed in each `Deny` entry and
emits telemetry via the paired `AuditDenied` entry. Users see a Windows notification
toast and receive an "The media is write protected" error when they attempt a covered
write operation.

The companion audit file is documented at
[PolicyRules.Audit.xml](PolicyRules.Audit.md).

---

## Full content

```xml
<PolicyRules>
  <PolicyRule Id="{77d21842-eba0-44a7-a46a-1c0291b087e0}">
    <Name>Deny write+execute on removable storage</Name>
    <IncludedIdList>
      <GroupId>{18c18655-7803-4235-a811-3da676a1f197}</GroupId>
    </IncludedIdList>
    <ExcludedIdList></ExcludedIdList>
    <Entry Id="{f02a2942-2316-4a99-a2bb-f93ad66cec23}">
      <Type>Deny</Type>
      <Options>0</Options>
      <AccessMask>6</AccessMask>
    </Entry>
    <Entry Id="{f57c874b-4c4d-4ef6-8bfa-a824c4959cc2}">
      <Type>AuditDenied</Type>
      <Options>3</Options>
      <AccessMask>6</AccessMask>
    </Entry>
  </PolicyRule>
  <PolicyRule Id="{d1a03385-6742-4f39-b05f-7f7f5c5bee1e}">
    <Name>Deny write+execute on WPD</Name>
    <IncludedIdList>
      <GroupId>{b9854cf9-b7e3-4155-b0ec-5031d44657b3}</GroupId>
    </IncludedIdList>
    <ExcludedIdList></ExcludedIdList>
    <Entry Id="{daf45292-2d46-4dc8-8304-bcfc1919b981}">
      <Type>Deny</Type>
      <Options>0</Options>
      <AccessMask>48</AccessMask>
    </Entry>
    <Entry Id="{8b6aaf1f-0ddc-4b78-8bcb-6dd0f317bfbb}">
      <Type>AuditDenied</Type>
      <Options>3</Options>
      <AccessMask>48</AccessMask>
    </Entry>
  </PolicyRule>
  <PolicyRule Id="{f3c3878f-3133-4b5a-83e8-4b4b79c35591}">
    <Name>Deny write on optical</Name>
    <IncludedIdList>
      <GroupId>{c145b8d2-2799-469b-8014-927e7dd9babf}</GroupId>
    </IncludedIdList>
    <ExcludedIdList></ExcludedIdList>
    <Entry Id="{7192cd3a-4a2f-4edf-b1d6-8d98b0f390b4}">
      <Type>Deny</Type>
      <Options>0</Options>
      <AccessMask>2</AccessMask>
    </Entry>
    <Entry Id="{96e8501e-3774-4a9f-bdbf-7fac062f128f}">
      <Type>AuditDenied</Type>
      <Options>3</Options>
      <AccessMask>2</AccessMask>
    </Entry>
  </PolicyRule>
</PolicyRules>
```

---

## Annotated walkthrough

### Why Deny and AuditDenied are always paired

Each rule in the Enforce file contains two entries: a `Deny` entry and an `AuditDenied`
entry with the same `AccessMask`. This pairing is intentional.

- **Deny** blocks the access. Without a Deny entry the engine has no instruction to
  block.
- **AuditDenied** emits the blocked-event telemetry. Without an AuditDenied entry the
  block still happens but no event appears in Defender XDR Advanced Hunting, the local
  event log, or the user notification subsystem. You get enforcement without
  observability.

Running Deny-only is valid XML and the engine accepts it, but you lose all evidence of
what was blocked. The starter policy always pairs them.

---

### Rule 1 -- Removable storage

```xml
<PolicyRule Id="{77d21842-eba0-44a7-a46a-1c0291b087e0}">
  <Name>Deny write+execute on removable storage</Name>
  <IncludedIdList>
    <GroupId>{18c18655-7803-4235-a811-3da676a1f197}</GroupId>
  </IncludedIdList>
  <ExcludedIdList></ExcludedIdList>
  <Entry Id="{f02a2942-2316-4a99-a2bb-f93ad66cec23}">
    <Type>Deny</Type>
    <Options>0</Options>
    <AccessMask>6</AccessMask>
  </Entry>
  <Entry Id="{f57c874b-4c4d-4ef6-8bfa-a824c4959cc2}">
    <Type>AuditDenied</Type>
    <Options>3</Options>
    <AccessMask>6</AccessMask>
  </Entry>
</PolicyRule>
```

- **PolicyRule Id**: The same GUID as in the Audit file. The GUID identifies the rule
  across files; the entry types determine what the engine does.
- **Deny / Options=0**: No notification and no separate audit event from the Deny
  entry itself. The notification and audit are handled by the AuditDenied entry below.
- **AuditDenied / Options=3**: 3 = audit event (2) + user notification toast (1).
  Users see a Windows notification that their write was blocked. The event appears in
  Defender XDR under `DeviceEvents | where ActionType == 'RemovableStoragePolicyTriggered'`.
- **AccessMask=6**: Write (2) + Execute (4). Read (1) is permitted.

---

### Rule 2 -- WPD / MTP devices

```xml
<Entry Id="{daf45292-2d46-4dc8-8304-bcfc1919b981}">
  <Type>Deny</Type>
  <Options>0</Options>
  <AccessMask>48</AccessMask>
</Entry>
<Entry Id="{8b6aaf1f-0ddc-4b78-8bcb-6dd0f317bfbb}">
  <Type>AuditDenied</Type>
  <Options>3</Options>
  <AccessMask>48</AccessMask>
</Entry>
```

- **AccessMask=48**: MTP Send (16) + MTP Receive-execute (32). Covers copying files to
  a phone or camera and executing files directly from MTP storage.
- The Deny entry uses Options=0 and the AuditDenied entry uses Options=3 for the same
  reason as Rule 1: split the block action from the telemetry/notification action.

---

### Rule 3 -- Optical drives

```xml
<Entry Id="{7192cd3a-4a2f-4edf-b1d6-8d98b0f390b4}">
  <Type>Deny</Type>
  <Options>0</Options>
  <AccessMask>2</AccessMask>
</Entry>
<Entry Id="{96e8501e-3774-4a9f-bdbf-7fac062f128f}">
  <Type>AuditDenied</Type>
  <Options>3</Options>
  <AccessMask>2</AccessMask>
</Entry>
```

- **AccessMask=2**: Write only. Blocks disc-burning write access on optical drives.
  Reading from an optical disc is not covered and remains unrestricted.
- On a device without an optical drive this rule matches no device and is effectively
  a no-op.

---

## Relationship to the Audit file

The `PolicyRule` and `GroupId` GUIDs in this file match the Audit file exactly. This is
intentional -- the two files represent the same policy intent at different severity
levels. When you switch from Audit to Enforce via `Set-DefenderDcPolicy`, only the rules
file is swapped; the groups file is shared.

See [audit-vs-enforce](../../concepts/audit-vs-enforce.md) for a conceptual comparison
and [PolicyRules.Audit.xml](PolicyRules.Audit.md) for the annotated audit file.
