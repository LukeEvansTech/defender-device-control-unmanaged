# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-22

### Added
- `Get-DefenderDcPolicy` - read current Device Control registry state
- `Invoke-DefenderDcOnboarding` - apply the canonical Local GPO Device Control registry surface
- `Invoke-DefenderDcUsbTest` - run a USB allow/block smoke-test
- `Set-DefenderDcPolicy` - write Device Control policy settings to the registry
- `Test-DefenderDcPolicy` - validate active policy against expected baseline
- `Test-DefenderDcPolicyXml` - validate Device Control XML policy files

[Unreleased]: https://github.com/LukeEvansTech/defender-device-control-unmanaged/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/LukeEvansTech/defender-device-control-unmanaged/releases/tag/v1.0.0
