Import-Module (Join-Path $PSScriptRoot '..\DefenderDeviceControlUnmanaged.psd1') -Force
# Plug approved devices in one by one; Ctrl+C when done.
Get-DefenderDcDevice -Watch -OutFile (Join-Path $PSScriptRoot 'approved.json')
