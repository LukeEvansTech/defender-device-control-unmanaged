# Roll back the policy

To remove the Device Control policy entirely, pass `-Mode Off` to `Set-DefenderDcPolicy`.
No XML paths are required.

```powershell
Set-DefenderDcPolicy -Mode Off
```

The cmdlet requires administrator elevation. It calls `gpupdate /force` and nudges
`Update-MpSignature` so the engine picks up the removal without waiting for the next
scheduled policy refresh.

---

## What gets removed

`-Mode Off` removes the following registry state under
`HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\`:

| Item | Description |
|---|---|
| `Policy Groups\PolicyGroups` (REG_SZ) | Path to the groups XML |
| `Policy Rules\PolicyRules` (REG_SZ) | Path to the rules XML |
| `Windows Defender\Device Control\DefaultEnforcement` | Default allow flag |
| `Windows Defender\Device Control\SecuredDevicesConfiguration` | Scoped device classes |
| `Windows Defender\Features\DeviceControlEnabled` | Master enable flag |

The `Policy Groups` and `Policy Rules` sub-keys themselves are also removed. The master
enable flag is set to 0 (not deleted, to avoid a Defender AM service restart) before
the key is cleaned up.

**The shipped policy XML files on disk are not touched.** They remain in the module
directory. The registry simply stops pointing at them. You can re-apply the policy at
any time.

---

## Verify rollback

```powershell
Test-DefenderDcPolicy -ExpectMode Off
```

All static checks should report PASS:

```
  PASS  Defender AM service enabled
  PASS  Defender antivirus enabled
  PASS  Device Control root key absent
  PASS  Features\DeviceControlEnabled absent or 0
  PASS  Engine reports DeviceControlState=Disabled

Static checks: ALL PASSED
```

---

## Note on engine-state stickiness

After rollback the registry is clean immediately, but `Get-MpComputerStatus` may still
report `DeviceControlState = Enabled` for up to a minute. The engine refreshes its
in-memory state on the next policy cycle rather than instantaneously. The
`Test-DefenderDcPolicy -ExpectMode Off` check for `DeviceControlState=Disabled` may
therefore fail briefly after rollback and then self-correct.

If the check is still failing after two minutes, see
[004-engine-state-stickiness](../troubleshooting/kb/004-engine-state-stickiness.md) for
diagnosis steps.

---

## Re-apply after rollback

Re-application is identical to first application. The cmdlet removes any lingering state
before writing:

```powershell
# Re-apply Audit
Set-DefenderDcPolicy -Mode Audit

# Re-apply Enforce
Set-DefenderDcPolicy -Mode Enforce

# Re-apply with custom XML
Set-DefenderDcPolicy -Mode Enforce `
    -GroupsXmlPath C:\MyPolicy\Groups.xml `
    -RulesXmlPath  C:\MyPolicy\Rules.xml
```

---

## Related

- [004-engine-state-stickiness](../troubleshooting/kb/004-engine-state-stickiness.md)
- [Set-DefenderDcPolicy reference](../reference/cmdlets/Set-DefenderDcPolicy.md)
