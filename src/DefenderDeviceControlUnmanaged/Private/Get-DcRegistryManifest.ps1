function Get-DcRegistryManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GroupsXmlPath,
        [Parameter(Mandatory)][string] $RulesXmlPath
    )

    $absolutePattern = '^([A-Za-z]:\\|/)' # Windows drive-letter or Unix root
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
