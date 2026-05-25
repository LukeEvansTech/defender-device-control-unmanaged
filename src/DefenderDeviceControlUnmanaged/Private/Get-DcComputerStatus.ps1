function Get-DcComputerStatus {
<#
.SYNOPSIS
    Thin wrapper over the real Defender Get-MpComputerStatus command.

.DESCRIPTION
    Indirection layer for testability. On Windows this simply forwards to
    ConfigDefender's Get-MpComputerStatus. Pester mocks this wrapper instead
    of the real command, which lets tests run on macOS where it is absent.

    Note: Get-MpComputerStatus is a CDXML-backed Function in the in-box
    Defender module, not a Cmdlet. The -CommandType filter must allow
    Function or this wrapper raises CommandNotFoundException on Windows.
#>
    [CmdletBinding()]
    [OutputType([object])]
    param()
    & (Get-Command -Name Get-MpComputerStatus -CommandType Function -ErrorAction Stop)
}
