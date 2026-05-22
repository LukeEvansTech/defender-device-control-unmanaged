# Onboard to Microsoft Defender for Endpoint

The Defender Device Control engine only activates when the host is onboarded to
Microsoft Defender for Endpoint (MDE). Registry writes succeed on any Windows 11 box,
but the engine ignores the policy until the Sense service is running and the
`OnboardingState` marker is set.

`Invoke-DefenderDcOnboarding` wraps the per-tenant onboarding script with pre-flight
checks, automatic ZIP detection, extraction, elevated execution, and post-flight
verification in a single command.

---

## Prerequisites

- An MDE tenant with an active license: Defender for Business, Plan 1, or Plan 2.
- A Windows 11 device that is **not** yet onboarded (Sense service present but not
  running, or absent).
- Administrator elevation on the target device.

---

## Step 1: Download the onboarding package

1. Open [security.microsoft.com](https://security.microsoft.com) and sign in with a
   Global Administrator or Security Administrator account.
2. Go to **Settings** > **Endpoints** > **Device management** > **Onboarding**.
3. Select **Windows 10 and 11** as the operating system.
4. Select **Local Script** as the deployment method.
5. Click **Download onboarding package**.

The downloaded file is a ZIP whose name includes your tenant ID and the string
`WindowsDefenderATPOnboarding`. The exact name varies by tenant -- for example:

```
WindowsDefenderATPOnboardingPackage.zip
```

Save it to your `Downloads` folder. The cmdlet searches `$env:USERPROFILE\Downloads\`
for any file matching `*WindowsDefenderATPOnboarding*.zip` and uses the newest match.

---

## Step 2: Open an elevated PowerShell

Right-click **Windows Terminal** (or **PowerShell**) and choose **Run as
administrator**. Import the module if you have not already done so:

```powershell
Import-Module DefenderDeviceControlUnmanaged
```

---

## Step 3: Run the cmdlet

Auto-detect the onboarding ZIP from Downloads:

```powershell
Invoke-DefenderDcOnboarding
```

Or pass the path explicitly if you saved the ZIP to a non-default location:

```powershell
Invoke-DefenderDcOnboarding -OnboardingScript 'C:\Staging\WindowsDefenderATPOnboardingPackage.zip'
```

You can also pass the extracted `.cmd` file directly:

```powershell
Invoke-DefenderDcOnboarding -OnboardingScript 'C:\Extracted\WindowsDefenderATPOnboardingScript.cmd'
```

---

## What the cmdlet does

The cmdlet runs four numbered phases and prints a real-time status banner.

**[1/4] Pre-flight**
Verifies that the Defender AM service is enabled, the Sense service is installed on the
box, and the device is not already onboarded. If the box is already onboarded
(Sense=Running and OnboardingState=1), the cmdlet throws and exits -- do not re-onboard
without offboarding first.

**[2/4] Locate onboarding script**
If `-OnboardingScript` is not supplied, the cmdlet scans `Downloads` for ZIPs matching
`*WindowsDefenderATPOnboarding*.zip`, selects the newest, extracts it to a temp
directory, and locates `WindowsDefenderATP*OnboardingScript.cmd` inside. The temp
directory is cleaned up in the `finally` block regardless of outcome.

**[3/4] Run onboarding script**
Calls `cmd.exe /c "<path-to-.cmd>"` under the current elevated session. Waits for exit.
A non-zero exit code is logged as a warning rather than a hard stop; post-flight checks
capture the actual resulting state.

After the script exits, the cmdlet waits `SkipPostFlightWait` seconds (default 30)
before reading service and registry state. The Sense service start and the OnboardingState
registry marker are asynchronous -- the default wait is intentionally conservative.

**[4/4] Post-flight verification**
Checks and reports:
- `Sense.Status = Running`
- `Sense.StartType = Automatic`
- `OnboardingState = 1` (HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat
  Protection\Status)
- `OrgId` is a non-empty string (the tenant GUID)

A transcript is saved to `$env:LOCALAPPDATA\DefenderDeviceControlUnmanaged\` for
review if any check fails.

---

## Expected post-flight output

```
  PASS  Defender AM service enabled
  PASS  Sense service is installed
  PASS  Sense.Status = Running
  PASS  Sense.StartType = Automatic
  PASS  OnboardingState = 1
  PASS  OrgId is populated

 Invoke-DefenderDcOnboarding: ALL POST-FLIGHT CHECKS PASSED
```

The cmdlet returns a `pscustomobject` with `SenseStatus`, `SenseStartType`,
`OnboardingState`, `OrgId`, `Failures`, and `TranscriptPath` for scripted inspection.

---

## Related

- [mde-attach-gate concept](../concepts/mde-attach-gate.md)
- [Invoke-DefenderDcOnboarding reference](../reference/cmdlets/Invoke-DefenderDcOnboarding.md)
