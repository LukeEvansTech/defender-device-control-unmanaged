function Get-DcMpCmdRunPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $installPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender' -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
    if ($installPath -and (Test-Path -LiteralPath (Join-Path $installPath 'MpCmdRun.exe'))) {
        return (Join-Path $installPath 'MpCmdRun.exe')
    }

    $platform = Get-ChildItem 'C:\ProgramData\Microsoft\Windows Defender\Platform\*\MpCmdRun.exe' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($platform) { return $platform.FullName }

    return $null
}
