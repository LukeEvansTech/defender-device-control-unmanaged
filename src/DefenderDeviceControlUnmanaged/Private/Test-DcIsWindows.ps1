function Test-DcIsWindows {
    <#
    .SYNOPSIS
        True when running on Windows (PS 5.1 or PowerShell 7+).
    .DESCRIPTION
        PS 5.1 has no automatic $IsWindows variable; the short-circuit -or
        only evaluates $IsWindows on Core, keeping StrictMode happy. Separate
        function so unit tests can mock the platform.
    .EXAMPLE
        Test-DcIsWindows
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows
}
