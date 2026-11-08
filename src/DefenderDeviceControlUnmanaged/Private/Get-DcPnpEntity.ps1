function Get-DcPnpEntity {
    <#
    .SYNOPSIS
        Enumerate Win32_PnPEntity instances (thin Get-CimInstance wrapper).
    .DESCRIPTION
        Exists so Get-DefenderDcDevice tests can mock PnP enumeration without
        CIM, mirroring how Get-DcComputerStatus wraps Get-MpComputerStatus.
    .EXAMPLE
        Get-DcPnpEntity
    #>
    [CmdletBinding()]
    param()

    Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
}
