function Get-DcRegistryValue {
<#
.SYNOPSIS
    Read a single named registry value, returning $null if the key or value is absent.

.DESCRIPTION
    Thin wrapper over Get-ItemProperty that swallows "missing key" / "missing value"
    errors and returns $null. Use to flatten the common four-line
    "Get-ItemProperty; if not null then read the named property" pattern.

.PARAMETER Path
    Registry key path (e.g. 'HKLM:\SOFTWARE\Policies\...').

.PARAMETER Name
    Named value under the key.
#>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $prop = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $prop) { return $null }
    return $prop.$Name
}
