# Policy XML format

`MpCmdRun.exe -DeviceControl -TestPolicyXml` is the engine-side XML
validator that `Set-DefenderDcPolicy` and `Test-DefenderDcPolicyXml` both
call before any registry write. Its parser is byte-greedy: it reads the
raw byte stream of the file, not a DOM. Four format constraints follow
directly from this, and violating any one of them produces a parse
rejection with no output other than a non-zero exit code.

`Set-DefenderDcPolicy` runs this validator as a pre-flight step, so
malformed files are caught before the registry is touched. If you are
authoring custom XML, validate it first with
`Test-DefenderDcPolicyXml` before attempting a deploy.

## Constraint 1: No UTF-8 BOM

The file must start with the first byte of the XML content -- not with
the UTF-8 byte order mark `EF BB BF`.

**Correct** -- file starts with `<`:

```xml
<Groups>
  <Group Id="{...}" Type="Device">
```

**Wrong** -- file starts with the BOM bytes (invisible in most editors):

```
EF BB BF <Groups>
```

Editors such as Notepad and some versions of Visual Studio Code can
silently add a BOM when saving UTF-8 files. If `Test-DefenderDcPolicyXml`
fails on a file that looks correct, check for a BOM with a hex editor
or by running `Format-Hex -Path .\PolicyGroups.xml | Select-Object -First 1`
and confirming the first three bytes are not `EF BB BF`.

## Constraint 2: No XML declaration

The file must not begin with an `<?xml ... ?>` processing instruction,
even inside an XML comment.

**Correct:**

```xml
<Groups>
```

**Wrong:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<Groups>
```

The byte-greedy parser does not recognise the processing instruction
syntax and rejects the file.

## Constraint 3: Name as a child element

On `<PolicyRule>` elements, the rule name must appear as a child element,
not as an attribute.

**Correct:**

```xml
<PolicyRule Id="{...}" Action="Deny">
  <Name>Deny USB Write</Name>
  ...
</PolicyRule>
```

**Wrong:**

```xml
<PolicyRule Id="{...}" Action="Deny" Name="Deny USB Write">
```

This is inconsistent with how XML naming works in other Microsoft policy
schemas, so it catches people who copy from those schemas. The parser
rejects the attribute form.

## Constraint 4: Options bitmask in 0..3

`<Options>` is a 2-bit field. Any value outside 0, 1, 2, 3 causes a
parse rejection.

**Correct:**

```xml
<Options>2</Options>
```

**Wrong:**

```xml
<Options>4</Options>
```

The meaning of the valid values is described in
[Audit vs Enforce](audit-vs-enforce.md). In practice you will use
`0` (no audit), `2` (AuditAllowed), or `3` (AuditDenied). Value `1`
is reserved.

## Validate before deploy

`Test-DefenderDcPolicyXml` validates a file through three layers:
structural XML parse, the four format constraints above, and the
`MpCmdRun.exe` engine check. Each constraint failure prints the
constraint name so you know exactly which rule is violated.

```powershell
Test-DefenderDcPolicyXml -Path .\MyGroups.xml -Kind Groups
Test-DefenderDcPolicyXml -Path .\MyRules.xml  -Kind Rules
```

Returns `$true` on success, `$false` on failure. Exits non-zero on
failure, so it can be used as a gate in a script before calling
`Set-DefenderDcPolicy`.

For worked examples of the shipped starter XML files, see
[Example XML reference](../reference/example-xml/PolicyGroups.md). For
how to extend the policy with additional device categories, see
[Extend device categories](../howto/extend-device-categories.md).
