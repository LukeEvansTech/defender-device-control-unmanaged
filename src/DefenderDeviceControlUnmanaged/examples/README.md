# Examples - clone-and-run path

These scripts wrap the module cmdlets for boxes that cannot reach
PowerShell Gallery (no egress, locked-down environments). They assume
you have the full repo on disk and that you run them from an elevated
PowerShell.

```powershell
Import-Module .\src\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1 -Force
.\src\DefenderDeviceControlUnmanaged\examples\Apply-Audit.ps1
```

If the module is already installed from PowerShell Gallery, prefer
calling the cmdlets directly - these scripts are only for the
no-Gallery path.
