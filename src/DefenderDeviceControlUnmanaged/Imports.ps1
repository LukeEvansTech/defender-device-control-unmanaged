# Module-scope variables (script-scoped, available to all dot-sourced
# Public + Private files at module-load time). The build process merges
# this file into the published psm1; for local development it is
# dot-sourced by the loader psm1.

# Canonical Defender Device Control GPO registry surface, derived from
# microsoft/mdatp-devicecontrol/windows/WindowsDefender.admx.
$script:DcRoot           = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control'
$script:DcGroupsKey      = "$script:DcRoot\Policy Groups"
$script:DcRulesKey       = "$script:DcRoot\Policy Rules"
$script:DcFeatures       = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Features'
$script:DcSecuredClasses = 'RemovableMediaDevices|CdRomDevices|WpdDevices'
