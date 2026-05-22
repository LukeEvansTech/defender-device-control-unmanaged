function Test-IsElevated {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
