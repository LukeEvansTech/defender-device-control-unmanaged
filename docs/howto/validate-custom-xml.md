# Validate custom XML

Before writing anything to the registry, validate your policy XML with
`Test-DefenderDcPolicyXml`. The Defender engine's XML parser is byte-greedy: a stray
BOM or a misplaced attribute causes silent rejection. Catching the problem before deploy
saves a registry write cycle and the 30-60 seconds it takes the engine to attempt a
refresh.

---

## The three validation layers

`Test-DefenderDcPolicyXml` applies checks in order. It returns `$false` and emits a
named `Write-Error` as soon as any layer fails -- the error text tells you the exact
constraint that was violated.

**Layer 2a -- BOM check (runs first)**
Reads the raw bytes of the file. If the first three bytes are `EF BB BF` (UTF-8 BOM),
the file is rejected immediately. MpCmdRun rejects BOM-prefixed XML without explanation.
Save your file as "UTF-8 without BOM" (the default in most editors when you choose UTF-8
explicitly).

**Layer 2b -- XML declaration check**
If the trimmed content starts with `<?xml`, the file is rejected. MpCmdRun does not
accept files that include the XML declaration. The file must begin directly with the
root element (`<Groups>` or `<PolicyRules>`).

**Layer 1 -- Structural parse**
The content is parsed as XML. If the parse fails, the exception message is reported.
After a successful parse, the root element name is checked: `<Groups>` for
`-Kind Groups`, `<PolicyRules>` for `-Kind Rules`.

**Layer 2c -- Rules-specific format constraints** (only for `-Kind Rules`)
- Each `<PolicyRule>` must carry `Name` as a child element (`<Name>...</Name>`), not
  as an XML attribute. MpCmdRun requires the element form.
- Each `<Entry>/<Options>` value must be in the range 0..3. Options is a 2-bit bitmask.

**Layer 3 -- Engine-side via MpCmdRun**
Calls `MpCmdRun.exe -DeviceControl -TestPolicyXml` against the file. If MpCmdRun.exe is
absent (for example on a CI runner that does not have Defender installed), this layer is
skipped silently. On a Windows device with Defender, this runs the engine's own parser
and catches any remaining structural issues not covered by layers 1 and 2.

---

## Worked examples

### Good XML -- returns True

```powershell
Test-DefenderDcPolicyXml -Path .\MyGroups.xml -Kind Groups
# True
```

No output other than the return value when all checks pass.

---

### XML with a UTF-8 BOM -- returns False

```powershell
Test-DefenderDcPolicyXml -Path .\Groups-with-bom.xml -Kind Groups
# Write-Error: Test-DefenderDcPolicyXml: file starts with a UTF-8 BOM.
#   MpCmdRun rejects BOM-prefixed XML. Save the file as UTF-8 without BOM.
# False
```

In VS Code: File > Save with Encoding > UTF-8 (not "UTF-8 with BOM").
In Notepad: the default "UTF-8" option writes no BOM; "UTF-8 BOM" does.

---

### XML with an `<?xml?>` declaration -- returns False

```powershell
Test-DefenderDcPolicyXml -Path .\Rules-with-decl.xml -Kind Rules
# Write-Error: Test-DefenderDcPolicyXml: file begins with an xml declaration
#   (<?xml ... ?>). MpCmdRun rejects XML files that include the declaration;
#   remove it and start the file with the root element directly.
# False
```

Delete the first line of the file so it starts with `<PolicyRules>` or `<Groups>`.

---

### PolicyRule with `Name` as an attribute -- returns False

```xml
<!-- Bad: Name as attribute -->
<PolicyRule Id="{...}" Name="Block USB">
```

```powershell
Test-DefenderDcPolicyXml -Path .\Rules-name-attr.xml -Kind Rules
# Write-Error: Test-DefenderDcPolicyXml: PolicyRule Id='{...}' has Name as an
#   attribute. MpCmdRun requires Name as a child element (<Name>...</Name>).
# False
```

Fix: move the name into a child element.

```xml
<!-- Correct -->
<PolicyRule Id="{...}">
  <Name>Block USB</Name>
```

---

### Options value out of range -- returns False

```xml
<Options>7</Options>
```

```powershell
Test-DefenderDcPolicyXml -Path .\Rules-bad-options.xml -Kind Rules
# Write-Error: Test-DefenderDcPolicyXml: Entry Id='{...}' has <Options>7</Options>.
#   The Options bitmask is 2-bit; valid values are 0, 1, 2, or 3.
# False
```

Valid values: `0` (no audit), `1` (user-facing notification only), `2` (silent audit
event), `3` (notification + audit event).

---

## Layer 3 on CI

If you run validation in a CI pipeline that does not have Defender installed, layer 3 is
skipped silently and the function still returns `$true` if layers 1 and 2 pass. No flag
or warning is emitted for the skip. This is intentional: CI pipelines validate schema
and format; the engine-side check runs on the target device.

---

## Related

- [policy-xml-format concept](../concepts/policy-xml-format.md)
- [Test-DefenderDcPolicyXml reference](../reference/cmdlets/Test-DefenderDcPolicyXml.md)
