function Read-DcPolicyXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Read-DcPolicyXml: file not found: $Path"
    }

    [xml]$doc = Get-Content -LiteralPath $Path -Raw

    $rootName = $doc.DocumentElement.LocalName

    if ($rootName -eq 'Groups') {
        $kind = 'Group'
        $nodes = @($doc.Groups.Group)
    } elseif ($rootName -eq 'PolicyRules') {
        $kind = 'Rule'
        $nodes = @($doc.PolicyRules.PolicyRule)
    } else {
        throw "Read-DcPolicyXml: $Path does not contain <Groups> or <PolicyRules> as the document element."
    }

    foreach ($n in $nodes) {
        $idAttr = $n.Attributes['Id']
        if ($null -eq $idAttr -or [string]::IsNullOrWhiteSpace($idAttr.Value)) {
            throw "Read-DcPolicyXml: $Path contains a <$($n.LocalName)> element with no Id attribute."
        }
        if ($kind -eq 'Rule') {
            $entries = @($n.SelectNodes('Entry'))
            if ($entries.Count -lt 1) {
                throw "Read-DcPolicyXml: $Path PolicyRule $($idAttr.Value) has no <Entry> elements."
            }
        }
        [pscustomobject]@{
            Kind   = $kind
            Guid   = $idAttr.Value
            RawXml = $n.OuterXml
        }
    }
}
