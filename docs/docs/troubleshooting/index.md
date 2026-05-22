# Troubleshooting

Symptom-driven diagnostic ladder. Each entry follows the same shape:

- **Symptom** -- what you see
- **Probe** -- commands to disambiguate the cause
- **Fix** -- action per cause
- **See also** -- KB / FAQ references

Entries are ordered roughly by likelihood from a fresh deployment.
For specific gotchas, the KB articles in [`kb/`](kb/) carry the
deeper background.

---

## 1. MpCmdRun rejects the policy XML

**Symptom**

`Set-DefenderDcPolicy` aborts during pre-flight with one of:

```
Failed to parse policy: 0xc00ce556
Failed to parse policy: 0x80070057
```

No registry writes occur (the validation is a pre-flight gate).

**Probe**

Re-run the validator directly to confirm which file is rejected and
which error code is current:

```powershell
& "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -DeviceControl -TestPolicyXml -Groups (Resolve-Path .\src\DefenderDeviceControlUnmanaged\policy\PolicyGroups.xml)
& "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -DeviceControl -TestPolicyXml -Rules  (Resolve-Path .\src\DefenderDeviceControlUnmanaged\policy\PolicyRules.Enforce.xml)
```

Then check the file for the four format constraints:

```powershell
# Check 1: BOM present?
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path .\src\DefenderDeviceControlUnmanaged\policy\PolicyGroups.xml))
'{0:X2} {1:X2} {2:X2}' -f $bytes[0], $bytes[1], $bytes[2]
# Expect: '3C 47 72'  (<Gr...)  Bad: 'EF BB BF' (BOM)

# Check 2: starts with <?xml?
Get-Content -Path .\src\DefenderDeviceControlUnmanaged\policy\PolicyGroups.xml -TotalCount 1
# Expect: '<Groups>'  Bad: '<?xml version=...'
```

**Fix**

See [KB-001: MpCmdRun rejects XML](kb/001-mpcmdrun-rejects-xml.md)
for the four-point fix list: remove BOM, remove the `<?xml ... ?>`
declaration, move `Name` from attribute to child element, ensure
`<Options>` value is 0-3.

**See also**

- [KB-001: MpCmdRun rejects XML](kb/001-mpcmdrun-rejects-xml.md)
- The `.gitattributes` file in the repo root pins XML files to
  LF + no-BOM, so if you are editing XMLs outside Git you may
  reintroduce the BOM.

---

## 2. Set-DefenderDcPolicy succeeded but USB write still works

**Symptom**

`Set-DefenderDcPolicy -Mode Enforce` reported success. Registry
shows the policy. USB write still completes without error.

**Probe**

Two possible causes -- disambiguate in this order:

```powershell
# Probe A: is the engine actually enforcing? (MDE attach gate)
(Get-MpComputerStatus).DeviceControlState
# Expect: Enforce
# Bad:   Disabled  -> MDE attach missing, see KB-002

# Probe B: was the USB already mounted before the policy was applied?
(Get-Volume | Where-Object DriveType -eq Removable | Select-Object DriveLetter, OperationalStatus | Format-Table | Out-String).Trim()
# Already-mounted devices keep the pre-Apply policy until the handle closes.
```

**Fix**

- **Probe A returned Disabled** -- onboard the box to MDE per
  [KB-002: MDE attach gate](kb/002-mde-attach-gate.md). MDE
  onboarding is required for Defender Device Control to activate;
  without it the policy registry is populated but enforcement stays
  dormant.
- **Probe B device already mounted** -- unplug the device, wait 5
  seconds, replug. Retry the write.

**See also**

- [KB-002: MDE attach gate](kb/002-mde-attach-gate.md)
- [FAQ: Already-mounted devices](../faq.md#q-already-mounted)

---

## 3. Invoke-DefenderDcOnboarding aborts with "no onboarding ZIP found"

**Symptom**

```
ERROR: No onboarding ZIP found matching glob '*WindowsDefenderATPOnboarding*.zip'
       in C:\Users\<you>\Downloads\
```

**Probe**

```powershell
Get-ChildItem $env:USERPROFILE\Downloads\*.zip | Select-Object Name, LastWriteTime, Length
```

Look for any filename containing `WindowsDefenderATPOnboarding`.

**Fix**

- **ZIP is in `Downloads\` but filename does not match.** Verify the
  filename. Microsoft generates per-tenant ZIPs with variant prefixes
  (e.g., `GatewayWindowsDefenderATPOnboardingPackage.zip`). The
  cmdlet auto-detects any `*WindowsDefenderATPOnboarding*.zip` in
  `Downloads`. If the file has been renamed manually, either restore
  the original name or pass:

```powershell
Invoke-DefenderDcOnboarding -OnboardingScript "C:\Path\To\YourFile.zip"
```

- **ZIP is in a different folder.** Move it to `Downloads\` or use
  `-OnboardingScript <full-path>`.
- **ZIP has not been downloaded yet.** Open
  `https://security.microsoft.com` -> Settings -> Endpoints ->
  Onboarding -> Local Script for Windows -> Download package. The ZIP
  is tenant-specific and valid for approximately 30 days.

**See also**

- [How-to: Onboard to MDE](../howto/onboard-to-mde.md)

---

## 4. Invoke-DefenderDcOnboarding post-flight reports OnboardingState=0 or Sense not Running

**Symptom**

The inner `.cmd` ran (transcript shows "SUCCESS" lines), but the
post-flight check fails:

```
[FAIL] Expected OnboardingState=1, got 0
[FAIL] Expected Sense Running+Automatic, got Stopped+Manual
```

**Probe**

```powershell
# Confirm registry state directly
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' | Select-Object OnboardingState, OrgId

# Confirm Sense service
Get-Service Sense | Format-Table Name, Status, StartType
```

**Fix**

- **Tenant ZIP expired.** Per-tenant ZIPs are valid approximately 30 days from
  generation. Re-download from the portal and re-run.
- **Proxy or TLS interception is mangling the call-home.** MDE
  onboarding calls Microsoft endpoints; if a proxy intercepts and
  re-signs TLS, the certificate pin can fail. Check for proxy or
  inspection in the network path; either bypass for the onboarding
  endpoints or use a box with direct internet egress.
- **Stale partial onboarding.** Run the matching offboarding script
  (also downloadable from the portal), wait 5 minutes, then re-run
  `Invoke-DefenderDcOnboarding` with a fresh ZIP. This module does not
  ship an offboarding wrapper.

**See also**

- [How-to: Onboard to MDE](../howto/onboard-to-mde.md)
- [KB-002: MDE attach gate](kb/002-mde-attach-gate.md)

---

## 5. Invoke-DefenderDcUsbTest reports PASS but USB write still succeeds in real use

**Symptom**

`Invoke-DefenderDcUsbTest` exits 0 with all phases PASS. You plug in
a production USB stick -- write succeeds. Repeat with the test stick --
write blocked.

**Probe**

```powershell
# Is the device enumerated as RemovableMediaDevices?
Get-Disk | Where-Object BusType -in 'USB','SD' | Select-Object Number, FriendlyName, BusType, IsBoot
$diskNumber = <number from above>
Get-PnpDevice -InstanceId (Get-Disk -Number $diskNumber).Path | Select-Object Class, ClassGuid, FriendlyName
```

Look at `ClassGuid`. Compare to:

- Removable Media: `{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}`
- Fixed disks (NOT covered): `{53f56307-b6bf-11d0-94f2-00a0c91efb8b}`

Some USB enclosures (particularly large external HDDs) report as
`Fixed` rather than `Removable` -- neither the Defender DC policy nor
the kernel-filter RSA surface catches them under this configuration.

**Fix**

- **Device enumerated as Fixed.** This is out of scope for the current
  policy set. The Defender DC policy targets the RemovableMedia class
  GUID. If you need to cover Fixed-bus USB enclosures, the policy XMLs
  need an additional rule scoped to the Fixed class -- a policy
  authoring change, not a configuration tweak. See
  [How-to: Extend device categories](../howto/extend-device-categories.md).

**See also**

- [FAQ: Class-GUID mismatch](../faq.md#q-class-mismatch)
- [How-to: Extend device categories](../howto/extend-device-categories.md)

---

## 6. After Set-DefenderDcPolicy -Mode Off, DeviceControlState stays Enabled

**Symptom**

```powershell
Set-DefenderDcPolicy -Mode Off
# (reports success)

Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control'
# False

(Get-MpComputerStatus).DeviceControlState
# Enabled  (or Audit / Enforce)  -- appears inconsistent
```

**Probe**

```powershell
# Has the engine had time to refresh? (Refresh interval >60s observed)
$s = Get-MpComputerStatus
[PSCustomObject]@{
    State = $s.DeviceControlState
    LastUpdate = $s.DeviceControlPoliciesLastUpdated
    SecondsSinceLastUpdate = ((Get-Date) - $s.DeviceControlPoliciesLastUpdated).TotalSeconds
}
```

**Fix**

Wait 60-120 seconds and re-check. This is expected engine behaviour;
the registry is authoritative during the settle window. Real USB
writes succeed normally during the gap because the policy is gone --
only the cached `DeviceControlState` is stale.

```powershell
Start-Sleep -Seconds 90
(Get-MpComputerStatus).DeviceControlState
# Expected: Disabled
```

**See also**

- [KB-004: Engine state stickiness](kb/004-engine-state-stickiness.md)

---

## 7. Test-DefenderDcPolicy throws PropertyNotFoundException

**Symptom**

The verifier blows up with a stack trace ending in:

```
PropertyNotFoundException: The property 'DeviceControlEnabled' cannot be found on this object.
```

**Probe**

```powershell
$build = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
$build

# Does Get-MpPreference even expose DeviceControl* fields on this build?
Get-MpPreference | Get-Member -Name 'DeviceControl*'
```

**Fix**

On Windows 11 build 28000 (Canary), Microsoft's CIM provider omits
the `DeviceControl*` set on `Get-MpPreference`, and PowerShell's
strict-mode property access raises `PropertyNotFoundException`
instead of returning `$null`. The verifier reads
`Get-MpComputerStatus.DeviceControlState` and defensively probes
properties via `$obj.PSObject.Properties['Name']` -- if you are
running hand-typed diagnostics using `Get-MpPreference.DeviceControlEnabled`,
switch to the defensive form. See
[KB-005: Build 28000 CIM quirks](kb/005-build-28000-cim-quirks.md).

If you are on a production build (22H2 / 23H2 / 24H2) and seeing
this error, the property should be present -- capture the full stack
trace and check which script or command is performing the property access.

**See also**

- [KB-005: Build 28000 CIM quirks](kb/005-build-28000-cim-quirks.md)
- Source: `src/DefenderDeviceControlUnmanaged/Public/Test-DefenderDcPolicy.ps1`

---

## 8. Access denied on Set-DefenderDcPolicy itself (not on USB write)

**Symptom**

```
Set-ItemProperty : Requested registry access is not allowed.
```

While `Set-DefenderDcPolicy` is running. The script fails before any
policy is written.

**Probe**

```powershell
# Check 1: PowerShell elevated?
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Expected: True. False means re-launch elevated.

# Check 2: Tamper Protection mistakenly guarding the path?
# (it should NOT - we write under HKLM\SOFTWARE\Policies\, not the Defender engine tree)
$apath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control'
# If this throws Access Denied as Administrator, something else is restricting the policy tree.
```

**Fix**

- **Not elevated.** Right-click PowerShell -> "Run as Administrator",
  re-run the cmdlet.
- **Custom ACL on the policy tree.** Rare -- typically a remnant of
  a previous third-party endpoint product. Reset ACL on the
  `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` key to default
  (Administrators full control).
- **Tamper Protection interference.** Should not happen for the
  policy tree (Tamper Protection guards the engine-state tree, not the
  GPO surface). If it does, verify the cmdlet is writing to
  `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control`
  and not to `HKLM\SOFTWARE\Microsoft\Windows Defender\` (engine tree).

**See also**

- [FAQ: Does Tamper Protection block this?](../faq.md#q-tamper-protection)

---

## 9. PowerShell script fails to parse with cryptic errors

**Symptom**

```
At C:\...\Set-DefenderDcPolicy.ps1:42 char:5
+     if ($Mode -eq 'Audit') {
+     ~
Missing closing '}' in statement block.
```

The error points at a syntactically-valid line, often near (but not
at) the actual problem. Re-running gives the same error.

**Probe**

```powershell
# Find any non-ASCII bytes in the module files
Get-ChildItem -Path .\src\DefenderDeviceControlUnmanaged -Recurse -Filter *.ps1 | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $bad = ($bytes | Where-Object { $_ -ge 0x80 }).Count
    if ($bad -gt 0) {
        [PSCustomObject]@{ File = $_.Name; NonAsciiBytes = $bad }
    }
}
```

**Fix**

Windows PowerShell 5.1 reads `.ps1` files as Latin-1; any multi-byte
UTF-8 sequence (em-dash, smart quotes, accented characters) becomes
parser garbage. Keep `.ps1` source files ASCII-only.

If you pasted a transcript or hand-edited a script in a word processor
that auto-corrected `--` to an em-dash, re-edit in a plain text editor
(Notepad, VS Code) and replace any Unicode with ASCII equivalents.

**See also**

- [FAQ: PowerShell script parse errors](../faq.md#q-ps1-parse-errors)

---

## 10. Set-DefenderDcPolicy reports mid-manifest failure and auto-rolls back

**Symptom**

`Set-DefenderDcPolicy` writes 1-3 entries, then fails on one, then
logs that it is rolling back the writes that succeeded:

```
[OK]   Set DefaultEnforcement = 1
[OK]   Set SecuredDevicesConfiguration = RemovableMediaDevices|...
[FAIL] Set PolicyGroups = <path>: <error>
[INFO] Rolling back 2 writes that succeeded before failure
```

**Probe**

Read the rollback log to identify the specific write that failed.
Common patterns on the `[FAIL]` line:

- `Cannot find path 'HKLM:\SOFTWARE\Policies\...\Device Control\Policy Groups'`
  -> the script attempted `Set-ItemProperty` before `New-Item`
  created the subkey. Should not happen with current cmdlet version; report
  as a bug.
- `Requested registry access is not allowed.`
  -> see symptom 8 above.
- I/O or permission errors on the XML file path -- verify the XML files
  exist and are readable:

```powershell
Test-Path (Resolve-Path .\src\DefenderDeviceControlUnmanaged\policy\PolicyGroups.xml)
Test-Path (Resolve-Path .\src\DefenderDeviceControlUnmanaged\policy\PolicyRules.Enforce.xml)
```

**Fix**

The auto-rollback leaves the system in a clean state -- there is no
half-applied policy after a mid-manifest failure. Fix the underlying
cause and re-run `Set-DefenderDcPolicy`. No manual cleanup of partial
writes is needed.

If the rollback itself failed (rare), the cmdlet logs which writes
remain. Remove them manually:

```powershell
Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control' -Recurse -Force
Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Features' -Name DeviceControlEnabled -ErrorAction SilentlyContinue
```

**See also**

- [FAQ: Mid-manifest rollback](../faq.md#q-mid-rollback)
- Source: `src/DefenderDeviceControlUnmanaged/Public/Set-DefenderDcPolicy.ps1`
