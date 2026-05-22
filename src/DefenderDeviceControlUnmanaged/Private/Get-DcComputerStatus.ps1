function Get-DcComputerStatus {
<#
.SYNOPSIS
    Thin wrapper over the real Defender Get-MpComputerStatus cmdlet.

.DESCRIPTION
    Indirection layer for testability. On Windows this simply forwards to
    ConfigDefender's Get-MpComputerStatus. Pester mocks this wrapper instead
    of the real cmdlet, which lets tests run on macOS where the real cmdlet
    is absent.
#>
    [CmdletBinding()]
    param()
    & (Get-Command -Name Get-MpComputerStatus -CommandType Cmdlet -ErrorAction Stop)
}
