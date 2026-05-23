function Test-DefenderDcPolicyXml {
<#
.SYNOPSIS
    Validate a Defender Device Control policy XML before deploying it.

.DESCRIPTION
    Three-layer validation for a Groups or Rules policy XML:
      1. Structural parse - is it valid XML, with the expected root element?
      2. Format constraints - no UTF-8 BOM, no <?xml ... ?> declaration,
         Name as child element (not attribute) on PolicyRule, Options
         bitmask in 0..3.
      3. Engine-side - MpCmdRun.exe -DeviceControl -TestPolicyXml (skipped
         silently if MpCmdRun.exe is not on this box, e.g. CI runners).

    Each layer fails with a specific, named error so authors of custom XML
    know exactly which constraint they violated. Returns $true on full pass,
    $false on any failure (plus a Write-Error describing which constraint).

.PARAMETER Path
    Path to the XML file to validate.

.PARAMETER Kind
    Groups (for a PolicyGroups XML) or Rules (for a PolicyRules XML).

.PARAMETER SkipEngineValidation
    Skip the final MpCmdRun.exe engine-side validation layer while keeping the
    file-exists, BOM, xml-declaration, structural, and Rules-specific checks.

.EXAMPLE
    Test-DefenderDcPolicyXml -Path .\MyGroups.xml -Kind Groups

    Validate a custom Groups XML.

.EXAMPLE
    Test-DefenderDcPolicyXml -Path .\MyRules.xml -Kind Rules

    Validate a custom Rules XML, including engine-side check on Windows.

.LINK
    https://lukeevanstech.github.io/defender-device-control-unmanaged/howto/validate-custom-xml/
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateSet('Groups','Rules')]
        [string] $Kind,

        [switch] $SkipEngineValidation
    )

    Set-StrictMode -Version Latest

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Error "Test-DefenderDcPolicyXml: file not found: $Path"
        return $false
    }

    # Layer 2a: BOM check
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Error "Test-DefenderDcPolicyXml: file starts with a UTF-8 BOM. MpCmdRun rejects BOM-prefixed XML. Save the file as UTF-8 without BOM."
        return $false
    }

    $content = Get-Content -LiteralPath $Path -Raw

    # Layer 2b: <?xml ... ?> declaration check
    if ($content.TrimStart() -match '^<\?xml') {
        Write-Error "Test-DefenderDcPolicyXml: file begins with an xml declaration (<?xml ... ?>). MpCmdRun rejects XML files that include the declaration; remove it and start the file with the root element directly."
        return $false
    }

    # Layer 1: structural parse
    try {
        [xml]$doc = $content
    } catch {
        Write-Error "Test-DefenderDcPolicyXml: XML failed to parse: $($_.Exception.Message)"
        return $false
    }

    $rootName = $doc.DocumentElement.LocalName
    $expectedRoot = if ($Kind -eq 'Groups') { 'Groups' } else { 'PolicyRules' }
    if ($rootName -ne $expectedRoot) {
        Write-Error "Test-DefenderDcPolicyXml: expected root element <$expectedRoot> for -Kind $Kind, found <$rootName>."
        return $false
    }

    # Layer 2c: Rules-specific format constraints
    if ($Kind -eq 'Rules') {
        $rules = @($doc.PolicyRules.PolicyRule)
        foreach ($r in $rules) {
            $nameAttr = $r.Attributes['Name']
            if ($null -ne $nameAttr) {
                Write-Error "Test-DefenderDcPolicyXml: PolicyRule Id='$($r.Id)' has Name as an attribute. MpCmdRun requires Name as a child element (<Name>...</Name>)."
                return $false
            }

            $entries = @($r.SelectNodes('Entry'))
            foreach ($e in $entries) {
                $opt = $e.SelectSingleNode('Options')
                if ($null -ne $opt) {
                    $v = [int]$opt.InnerText
                    if ($v -lt 0 -or $v -gt 3) {
                        Write-Error "Test-DefenderDcPolicyXml: Entry Id='$($e.Id)' has <Options>$v</Options>. The Options bitmask is 2-bit; valid values are 0, 1, 2, or 3."
                        return $false
                    }
                }
            }
        }
    }

    # Layer 2d: structural per-element checks via Read-DcPolicyXml — runs even when
    # -SkipEngineValidation is set so callers (e.g. Set-DefenderDcPolicy
    # -SkipMpCmdRunValidation) still get "every PolicyRule has at least one <Entry>"
    # and "every Group/PolicyRule has an Id attribute" enforcement before any
    # registry writes happen.
    try {
        Read-DcPolicyXml -Path $Path | Out-Null
    } catch {
        Write-Error "Test-DefenderDcPolicyXml: structural validation failed: $($_.Exception.Message)"
        return $false
    }

    # Layer 3: engine-side via MpCmdRun (skipped silently if MpCmdRun absent)
    if (-not $SkipEngineValidation) {
        try {
            Test-DcXmlWithMpCmdRun -XmlPath $Path -Kind $Kind
        } catch {
            Write-Error "Test-DefenderDcPolicyXml: engine-side validation failed: $($_.Exception.Message)"
            return $false
        }
    }

    return $true
}
