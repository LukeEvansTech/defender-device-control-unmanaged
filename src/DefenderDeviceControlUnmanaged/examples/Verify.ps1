#Requires -RunAsAdministrator
Import-Module (Join-Path $PSScriptRoot '..\DefenderDeviceControlUnmanaged.psd1') -Force
$current = Get-DefenderDcPolicy
Write-Host "Current mode: $($current.Mode)" -ForegroundColor Cyan
Test-DefenderDcPolicy -ExpectMode $current.Mode
