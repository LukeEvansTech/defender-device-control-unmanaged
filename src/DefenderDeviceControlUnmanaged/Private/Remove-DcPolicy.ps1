function Remove-DcPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    if (Test-Path -LiteralPath $script:DcRoot) {
        if ($PSCmdlet.ShouldProcess($script:DcRoot, 'Remove-Item -Recurse')) {
            Remove-Item -LiteralPath $script:DcRoot -Recurse -Force
        }
    }
    if (Test-Path -LiteralPath $script:DcFeatures) {
        $p = Get-ItemProperty -LiteralPath $script:DcFeatures -Name 'DeviceControlEnabled' -ErrorAction SilentlyContinue
        if ($null -ne $p) {
            if ($PSCmdlet.ShouldProcess("$script:DcFeatures\DeviceControlEnabled", 'Remove-ItemProperty')) {
                Remove-ItemProperty -LiteralPath $script:DcFeatures -Name 'DeviceControlEnabled' -Force
            }
        }
    }
}
