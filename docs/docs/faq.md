# FAQ

Questions typically asked before, during, or after deploying
DefenderDeviceControlUnmanaged to a Windows 11 Enterprise endpoint.
Each question has an explicit HTML anchor so other docs can link to it.

For symptom-driven debugging, see
[Troubleshooting](troubleshooting/index.md).

For scope boundaries, see [Concepts: Scope](concepts/scope.md).

---

## Scope and impact

<a id="q-what-blocked"></a>
### Q: What does this policy block, exactly?

A: Write and execute on three device classes -- Removable Disks
(USB sticks, USB HDDs), WPD/MTP (phones, cameras, portable media
players), and optical (CD/DVD/Blu-ray). Read is allowed everywhere.
Internal SATA/NVMe disks are not touched. HID devices (USB keyboards,
mice) are not on the secured-classes list and are not affected --
neither is USB charging or USB-PD.

<a id="q-toast"></a>
### Q: Will the user get a notification when a write is blocked?

A: Yes. Under Defender Device Control (MDE-attached path), a toast
notification fires from Windows Security with the message
`The media is write protected`.

<a id="q-hid"></a>
### Q: Does this block USB keyboards, mice, or charging?

A: No. HID-class devices are not on the secured-classes list
(`RemovableMediaDevices|CdRomDevices|WpdDevices`). USB charging is a
power-delivery function, not a storage class -- also unaffected. The
policy is targeted at storage transports, not the USB bus.

<a id="q-bitlocker"></a>
### Q: Does unlocking a BitLocker-to-Go stick grant write?

A: No. Both mechanisms operate at a layer above the
encryption/decryption boundary. A BitLocker-to-Go-encrypted USB stick
is still enumerated under the Removable Disks class GUID, so write is
denied regardless of whether the volume is unlocked.

Note: BitLocker-to-Go carve-outs (allowing write specifically to
BitLocker-encrypted sticks while denying unencrypted ones) are not in
scope for v1 of this module. If you need that pattern, it requires
custom policy XML authoring.

<a id="q-wpd-execute"></a>
### Q: Phones plugged in via USB -- what is covered?

A: WPD/MTP write is denied -- you cannot push files onto a phone via
the WPD transport. Read (file enumeration, pulling files off the
phone) is allowed. On-phone execute is not directly expressed by the
WPD policy -- WPD is a transfer protocol, not a filesystem with
execute semantics. In practice, "execute from phone" workflows copy
the binary to the target filesystem first; the target path's
enforcement catches that copy.

## Mechanism and scope

<a id="q-which-mechanism"></a>
### Q: Is this the only mechanism shipped? What about Intune or GPMC?

A: This module is a per-device unmanaged tool -- it configures the
same GPO-shaped registry surface that Intune Configuration Profiles and
GPMC Group Policy write, but it does so locally without a management
plane. It is the right tool for standalone or lightly-managed endpoints.

For fleet-scale rollout, use Intune (Configuration Profiles -> Device
Control) or GPMC pushing the equivalent `HKLM\SOFTWARE\Policies\
Microsoft\Windows Defender\Device Control` registry shape. The policy
XML files in this module's `src/DefenderDeviceControlUnmanaged/policy/`
directory are directly usable as source material for either approach.

<a id="q-fleet-rollout"></a>
### Q: Can I roll this out to a fleet from one command?

A: No. This is a per-box tool. Run it on each endpoint individually,
or script the invocation into an existing remote-execution wrapper
(PSRemoting, SCCM, etc.). For true fleet rollout at scale, use Intune
Configuration Profile or GPMC, which push the same underlying registry
shape without requiring per-box script execution.

<a id="q-per-user-sid"></a>
### Q: Can I exempt a specific user account from the policy?

A: No. Per-user SID exemptions are not in scope for v1 of this module.
Defender Device Control policies apply machine-wide at the GPO surface
level. If you need per-user exemptions, that requires custom policy XML
authoring with SID-scoped rules, which is outside this module's current
scope.

## MDE and licensing

<a id="q-license-sku"></a>
### Q: Do I need a specific Defender SKU?

A: Yes. Defender Device Control is a feature of Microsoft Defender for
Endpoint and requires one of:

- Microsoft Defender for Endpoint **Plan 1**
- Microsoft Defender for Endpoint **Plan 2**
- Microsoft Defender for Business (the SMB-tier SKU)

Per Microsoft Learn:
<https://learn.microsoft.com/en-us/defender-endpoint/device-control-overview>

A Windows 11 Enterprise SKU alone is NOT sufficient -- Enterprise
includes the Defender Antivirus engine but not the MDE feature set
that activates Device Control. Without MDE onboarding, this module
will apply policy cleanly to the registry but enforcement will never
activate.

<a id="q-attach-gate"></a>
### Q: The cmdlet said it succeeded but DeviceControlState is still Disabled -- what is wrong?

A: Nothing in the module. The Defender engine has accepted the policy
(5007 events confirm the registry writes, and
`DeviceControlPoliciesLastUpdated` advances), but the engine is
license-gated and will not flip `DeviceControlState` to Audit/Enforce
without MDE attach. See
[KB-002: MDE attach gate](troubleshooting/kb/002-mde-attach-gate.md)
for the full explanation.

<a id="q-zip-filename"></a>
### Q: The onboarding ZIP filename in my Downloads looks different from the docs -- does that matter?

A: No. Microsoft generates the ZIP per tenant with a variant prefix
(examples seen: `GatewayWindowsDefenderATPOnboardingPackage.zip`,
`WindowsDefenderATPOnboardingPackage.zip`,
`<TenantPrefix>WindowsDefenderATPOnboardingPackage.zip`). The
`Invoke-DefenderDcOnboarding` cmdlet uses the glob
`*WindowsDefenderATPOnboarding*.zip` and handles all of these
automatically. If the file has been renamed, pass
`-OnboardingScript <full-path>` to override auto-detection.

## Operation

<a id="q-already-mounted"></a>
### Q: Already-mounted devices -- do they pick up the new policy?

A: No, not until the open handle closes. The Defender engine evaluates
policy at mount time; an already-mounted device keeps its pre-Apply
policy until it is unmounted. After applying a policy change, unplug
the USB stick (Windows safe-remove not required), wait 5 seconds,
replug. For phones or WPD devices, disconnect and reconnect.

<a id="q-no-events"></a>
### Q: I see toast notifications under Enforce but no entries in the local event log -- is that broken?

A: No, this is expected on MDE-onboarded recent builds. Defender DC
event telemetry routes via ETW to Defender XDR cloud, not to the local
Windows event log. To inspect per-event detail, open Advanced Hunting
in `https://security.microsoft.com` and run:

```kql
DeviceEvents
| where ActionType == "RemovableStoragePolicyTriggered"
| where DeviceName == "<hostname>"
| top 50 by Timestamp desc
```

See [No local event log on MDE builds](troubleshooting/kb/003-no-local-event-log.md)
for detail and latency expectations.

<a id="q-sticky-state"></a>
### Q: After Set-DefenderDcPolicy -Mode Off, DeviceControlState stayed Enabled for a while -- bug?

A: No, expected. The Defender engine has a cached view of policy state
that refreshes on a timer (>60s observed). The registry side is
authoritative and is clean immediately after Off; the engine cache
catches up within 1-2 minutes. Real USB writes succeed normally during
the gap because the policy is gone. See
[KB-004: Engine state stickiness](troubleshooting/kb/004-engine-state-stickiness.md).

<a id="q-xml-rejected"></a>
### Q: I edited the policy XML and now Set-DefenderDcPolicy fails XML validation -- what is wrong?

A: Almost always one of four format constraints that `MpCmdRun.exe`'s
parser is strict about:

1. UTF-8 BOM at the start of the file (must be no-BOM UTF-8).
2. `<?xml version=...?>` declaration (must start with the root element).
3. `Name` as an attribute on `<PolicyRule>` (must be a child element).
4. `<Options>` value >= 4 (valid range is 0-3 -- bitmask).

See [KB-001: MpCmdRun rejects XML](troubleshooting/kb/001-mpcmdrun-rejects-xml.md)
for the full fix list and validation command.

<a id="q-class-mismatch"></a>
### Q: A USB stick reports as Fixed not Removable -- does the policy cover it?

A: No. The policy targets the Removable Disks class GUID
(`{53f5630d-...}`). USB enclosures that report `BusType=USB` but
`Removable=False` (some external HDDs) are not caught. Spot-check
with `Get-Disk` after first plug-in; if you have devices that
enumerate as Fixed, the policy XMLs need an additional rule scoped to
the Fixed class -- a policy authoring change, not a configuration
tweak. See [How-to: Extend device categories](howto/extend-device-categories.md).

<a id="q-tamper-protection"></a>
### Q: Does Tamper Protection block this?

A: No. The module writes under
`HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\` -- the GPO
surface. Tamper Protection guards the engine-state tree at
`HKLM\SOFTWARE\Microsoft\Windows Defender\`, which this module does
not touch. Keep Tamper Protection on throughout deployment.

## Recovery

<a id="q-rollback"></a>
### Q: How do I fully remove this?

A: Run the Off mode, which removes the Device Control registry subtree
and runs `gpupdate /force`:

```powershell
Set-DefenderDcPolicy -Mode Off
```

The cmdlet is idempotent -- safe to run if the policy is not currently
applied. See [How-to: Roll back](howto/roll-back.md) for full
rollback instructions including restoring from a pre-deployment
registry backup.

<a id="q-ps1-parse-errors"></a>
### Q: A copy-pasted script broke with parser errors -- was it Unicode?

A: Almost certainly. Windows PowerShell 5.1 reads `.ps1` files as
Latin-1; any multi-byte UTF-8 sequence (em-dash from auto-correct,
smart quotes, accented characters) becomes parser garbage and produces
cryptic errors like `MissingEndCurlyBrace` near the bad byte. Keep
all `.ps1` files ASCII-only. If you pasted a transcript or hand-edited
in a word processor, re-edit in a plain text editor and replace any
Unicode with ASCII equivalents (`-` for em-dash, `"` for smart quotes).

<a id="q-mid-rollback"></a>
### Q: Set-DefenderDcPolicy reported a mid-manifest failure and rolled back -- is my system in a weird state?

A: No. The cmdlet writes its manifest inside a try/catch; on any
mid-write failure it logs the writes that succeeded, undoes them, and
re-throws the original error. The system never sits in a half-applied
state. Read the rollback log to see which write failed, fix the
underlying cause, and re-run.
