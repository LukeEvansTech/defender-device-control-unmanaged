#Requires -RunAsAdministrator
Import-Module (Join-Path $PSScriptRoot '..\DefenderDeviceControlUnmanaged.psd1') -Force
Set-DefenderDcPolicy -Mode Enforce
Test-DefenderDcPolicy -ExpectMode Enforce
