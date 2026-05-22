# KB-001: MpCmdRun rejects Defender Device Control policy XML

**Status:** Active
**Applies to:** DefenderDeviceControlUnmanaged
**Severity:** High

## Symptom

`MpCmdRun.exe -DeviceControl -TestPolicyXml` exits non-zero with one of:

```
Failed to parse policy: 0xc00ce556
Failed to parse policy: 0x80070057
```

Either error code surfaces during the `Set-DefenderDcPolicy` pre-flight
validation; the cmdlet aborts before any registry write.

`Set-DefenderDcPolicy` runs the test for both `PolicyGroups.xml`
and the chosen `PolicyRules.<Mode>.xml` and will not proceed unless both
pass.

## Cause

The Device Control XML parser inside `MpCmdRun.exe` is byte-greedy and
strict. It rejects valid-looking XML if any of four format constraints
are violated:

1. **UTF-8 BOM.** The file begins with bytes `EF BB BF` before the root
   element. The parser does not strip the BOM and fails with `0xc00ce556`.
2. **XML declaration.** A leading `<?xml version="1.0" encoding="utf-8"?>`
   line is rejected with `0x80070057`. Even text resembling `<?xml`
   inside a comment triggers the parser.
3. **`Name` as an attribute on `<PolicyRule>`.** The schema requires
   `<Name>...</Name>` as a child element. `<PolicyRule Id="..." Name="x">`
   is rejected.
4. **`<Options>` value out of range.** `<Options>` is a 2-bit bitmask;
   valid values are 0, 1, 2, 3. Anything >= 4 is rejected.

`.gitattributes` in this repo pins `src/DefenderDeviceControlUnmanaged/policy/*.xml`
to LF + no-BOM specifically to prevent (1) and (2) when files round-trip
through Git on Windows.

## Fix

1. Open the offending XML file in a text editor that can show and set the
   encoding without BOM (Notepad++, VS Code with "UTF-8" not
   "UTF-8 with BOM"). Re-save without BOM.
2. Remove any leading `<?xml ... ?>` line. The file must start with
   `<Groups>` (for `PolicyGroups.xml`) or `<PolicyRules>` (for
   `PolicyRules.*.xml`) directly.
3. Convert any `Name="x"` attribute on `<PolicyRule>` to a child element:

```xml
<PolicyRule Id="{...}" Group="{...}">
  <Name>Removable - allow read, deny write+execute (Audit)</Name>
  ...
</PolicyRule>
```

4. Check every `<Options>` value is 0, 1, 2, or 3. Conventional values:

   | Intent       | Value |
   |--------------|-------|
   | Deny         | 0     |
   | AuditAllowed | 2     |
   | AuditDenied  | 3     |

## How to validate the fix

You can run the validator directly without going through the cmdlet:

```powershell
& "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -DeviceControl -TestPolicyXml -Groups (Resolve-Path .\src\DefenderDeviceControlUnmanaged\policy\PolicyGroups.xml)
& "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -DeviceControl -TestPolicyXml -Rules  (Resolve-Path .\src\DefenderDeviceControlUnmanaged\policy\PolicyRules.Enforce.xml)
```

Expected: both commands exit 0 with a "Policy is valid" line. The
validator works unelevated.

Alternatively, the `Test-DefenderDcPolicyXml` cmdlet wraps the same
validation and surfaces a structured pass/fail result:

```powershell
Test-DefenderDcPolicyXml -GroupsXml .\src\DefenderDeviceControlUnmanaged\policy\PolicyGroups.xml `
                         -RulesXml  .\src\DefenderDeviceControlUnmanaged\policy\PolicyRules.Enforce.xml
```

## See also

- [KB-002: MDE attach gate](002-mde-attach-gate.md) -- even after
  valid XML, the engine will not enforce without MDE attach.
- [Reference: policy-xml-format](../../concepts/policy-xml-format.md)
- [How-to: Validate custom XML](../../howto/validate-custom-xml.md)
