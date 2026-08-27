# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - unreleased

### Added

- `New-DefenderDcPolicy`: craft custom Device Control policy XML from per-class
  restriction flags (`-Usb ReadOnly,DenyExecute`, `-Wpd ReadOnly`,
  `-Optical Block`, `Allow`) with approved-device exceptions
  (`-AllowHardwareId`, `-AllowDeviceFile`, pipeline). Emits the standard
  three-file shape (Groups + Audit/Enforce rules) with deterministic GUIDs so
  regeneration is byte-identical.
- `Get-DefenderDcDevice`: capture hardware identifiers of connected (or, with
  `-Watch`, newly plugged-in) USB/WPD/optical devices; `-OutFile` writes the
  JSON device list `New-DefenderDcPolicy -AllowDeviceFile` consumes.
- `Set-DefenderDcPolicy` accepts `New-DefenderDcPolicy` output from the
  pipeline; `-Mode` selects the audit or enforce rules file.

## [1.0.1] - 2026-05-25

### Fixed

- `Set-DefenderDcPolicy` (and `Test-DefenderDcPolicy`,
  `Get-DefenderDcPolicy`) crashed on every real Windows host with
  `Get-MpComputerStatus failed: The term 'Get-MpComputerStatus' is not
recognized`. The `Get-DcComputerStatus` wrapper filtered
  `Get-Command -CommandType Cmdlet`, but the in-box Defender module exposes
  `Get-MpComputerStatus` as a CDXML-backed Function, so the filter excluded it.
  Wrapper now uses `-CommandType Function`. Resolves
  [#3](https://github.com/LukeEvansTech/defender-device-control-unmanaged/issues/3).
- `-WhatIf` previews on `Set-DefenderDcPolicy`,
  `Invoke-DefenderDcOnboarding`, and `Invoke-DefenderDcUsbTest` crashed in
  their `finally` blocks with
  `An error occurred stopping transcription: The host is not currently
transcribing.` because `Start-Transcript` honors `$WhatIfPreference` and
  becomes a no-op while `Stop-Transcript` does not. All three `finally` blocks
  now guard `Stop-Transcript` with try/catch.

### Changed

- **Module internals refactored** for cohesion and prefix consistency. New Private helpers: `Get-DcRegistryValue`, `Start-DcTranscript`, `Write-DcCheckResult` (consolidate patterns previously duplicated across the public cmdlets). Renamed `Get-DefenderMpCmdRun` → `Get-DcMpCmdRunPath`, `Test-IsElevated` → `Test-DcIsElevated`.
- **API coherence:** `Test-DefenderDcPolicy.$ExpectMode` and `Invoke-DefenderDcUsbTest.$StartMode` carry `[Alias('Mode')]` so the canonical `-Mode` name works on all three policy cmdlets. `Invoke-DefenderDcOnboarding.$SkipPostFlightWait` renamed to `$PostFlightWaitSeconds` (the parameter sets a duration, it does not skip an action); old name kept as `[Alias()]`.
- **`SupportsShouldProcess`** added to `Invoke-DefenderDcOnboarding` and `Invoke-DefenderDcUsbTest`; the elevated `cmd.exe` onboarding run is now gated on `$PSCmdlet.ShouldProcess` so `-WhatIf` previews without firing.
- **Return objects carry PSTypeName tags** (`DefenderDeviceControlUnmanaged.Policy`, `.OnboardingResult`, `.UsbTestResult`) so a future `format.ps1xml` can attach without call-site churn.
- **`Set-DefenderDcPolicy`** routes XML validation through the public `Test-DefenderDcPolicyXml` (BOM / `<?xml?>` / `PolicyRule.Name`-as-child / Options-bitmask checks) regardless of whether the caller validated first. Typed `ErrorRecord` wrap on the `Get-DcComputerStatus` failure path preserves the inner exception + stack trace.
- **Real bugfix in `MarkdownRepair.ps1`:** the outer `foreach` iterator was shadowing the trim target on line 87; if/elseif branches assigned identical output. Collapsed to a single condition with the correct variable.
- **CI hardening:** forced TLS 1.2 in `Install-Module` steps (fixes intermittent `No match was found for ... module name 'Pester'` against PSGallery from Windows PowerShell 5.1). Bumped `actions/checkout@v5` and `actions/upload-artifact@v6` to clear the Node 20 deprecation. Pinned `runs-on: windows-2025`.

### Added

- **Engineering runbook** at [`docs/docs/runbook.md`](https://github.com/LukeEvansTech/defender-device-control-unmanaged/blob/main/docs/docs/runbook.md) — copy-and-run path for an engineer with a "USB read-only on this Windows 11 box" ticket; ~15 minutes from clean shell to verified policy.
- **26 new Pester tests (62 → 88 → 93).** 21 from the desloppify pass, plus 5 regression tests covering the two bugs above end-to-end on a real Windows host (wrapper resolution + unmocked `-WhatIf` transcript on all three public cmdlets). Red-green verified by reverting each fix and confirming the new tests fail with the exact regression error.

## [1.0.0] - 2026-05-22

### Added

- `Get-DefenderDcPolicy` - read current Device Control registry state
- `Invoke-DefenderDcOnboarding` - apply the canonical Local GPO Device Control registry surface
- `Invoke-DefenderDcUsbTest` - run a USB allow/block smoke-test
- `Set-DefenderDcPolicy` - write Device Control policy settings to the registry
- `Test-DefenderDcPolicy` - validate active policy against expected baseline
- `Test-DefenderDcPolicyXml` - validate Device Control XML policy files

[Unreleased]: https://github.com/LukeEvansTech/defender-device-control-unmanaged/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/LukeEvansTech/defender-device-control-unmanaged/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/LukeEvansTech/defender-device-control-unmanaged/releases/tag/v1.0.0
