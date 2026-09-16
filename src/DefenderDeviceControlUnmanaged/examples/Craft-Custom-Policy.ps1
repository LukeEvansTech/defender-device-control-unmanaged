#Requires -RunAsAdministrator
Import-Module (Join-Path $PSScriptRoot '..\DefenderDeviceControlUnmanaged.psd1') -Force
# USB read-only + no execute, WPD read-only, optical blocked; devices captured
# by Capture-Approved-Devices.ps1 are exempt. Applied in Audit mode first.
$approved = Join-Path $PSScriptRoot 'approved.json'
$splat = @{ Usb = 'ReadOnly','DenyExecute'; Wpd = 'ReadOnly'; Optical = 'Block'; OutputPath = Join-Path $PSScriptRoot 'custom-policy' }
if (Test-Path $approved) { $splat.AllowDeviceFile = $approved }
New-DefenderDcPolicy @splat | Set-DefenderDcPolicy -Mode Audit
Test-DefenderDcPolicy -ExpectMode Audit
