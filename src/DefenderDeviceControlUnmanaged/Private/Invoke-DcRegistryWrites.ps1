function Invoke-DcRegistryWrites {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]] $Manifest
    )

    foreach ($path in $script:DcRoot, $script:DcGroupsKey, $script:DcRulesKey, $script:DcFeatures) {
        if (-not (Test-Path -LiteralPath $path)) {
            if ($PSCmdlet.ShouldProcess($path, 'New-Item')) {
                New-Item -Path $path -Force | Out-Null
            }
        }
    }

    $written = New-Object System.Collections.Generic.List[string]
    $target = '(unstarted)'
    try {
        foreach ($w in $Manifest) {
            $target = "$($w.Path)\$($w.Name)"
            if ($PSCmdlet.ShouldProcess($target, "Set $($w.Type) (len=$($w.Value.ToString().Length))")) {
                New-ItemProperty -LiteralPath $w.Path -Name $w.Name -PropertyType $w.Type -Value $w.Value -Force | Out-Null
                $written.Add($target)
            }
        }
    } catch {
        Write-Warning "Invoke-DcRegistryWrites: write failed at '$target'. Auto-rolling back. Successful writes so far:"
        foreach ($t in $written) { Write-Warning "  - $t" }
        try { Remove-DcPolicy -WhatIf:$false } catch { Write-Warning "Rollback failed: $($_.Exception.Message)" }
        throw
    }
}
