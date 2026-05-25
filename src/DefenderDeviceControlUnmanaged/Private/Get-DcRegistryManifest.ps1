function Get-DcRegistryManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [string] $GroupsXmlPath,

        [Parameter(Mandatory)]
        [string] $RulesXmlPath
    )

    # IsPathRooted is platform-aware: on non-Windows it does not recognize Windows
    # drive-letter paths like 'C:\foo'. The regex keeps validation correct when the
    # Pester suite runs on macOS/Linux CI against Windows-style fixture paths.
    $absolutePattern = '^([A-Za-z]:\\|/)'
    if (-not ([System.IO.Path]::IsPathRooted($GroupsXmlPath) -or $GroupsXmlPath -match $absolutePattern)) {
        throw "Get-DcRegistryManifest: GroupsXmlPath must be an absolute path; got '$GroupsXmlPath'."
    }
    if (-not ([System.IO.Path]::IsPathRooted($RulesXmlPath) -or $RulesXmlPath -match $absolutePattern)) {
        throw "Get-DcRegistryManifest: RulesXmlPath must be an absolute path; got '$RulesXmlPath'."
    }

    $writes = New-Object System.Collections.Generic.List[object]
    $writes.Add([pscustomobject]@{ Path = $script:DcRoot;      Name = 'DefaultEnforcement';          Type = 'DWord';  Value = 1 })
    $writes.Add([pscustomobject]@{ Path = $script:DcRoot;      Name = 'SecuredDevicesConfiguration'; Type = 'String'; Value = $script:DcSecuredClasses })
    $writes.Add([pscustomobject]@{ Path = $script:DcGroupsKey; Name = 'PolicyGroups';                Type = 'String'; Value = $GroupsXmlPath })
    $writes.Add([pscustomobject]@{ Path = $script:DcRulesKey;  Name = 'PolicyRules';                 Type = 'String'; Value = $RulesXmlPath })
    $writes.Add([pscustomobject]@{ Path = $script:DcFeatures;  Name = 'DeviceControlEnabled';        Type = 'DWord';  Value = 1 })
    ,$writes.ToArray()
}
