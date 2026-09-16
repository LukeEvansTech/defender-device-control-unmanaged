function Add-DcDeviceRecord {
    <#
    .SYNOPSIS
        Append a captured device record to a JSON array file, deduped by
        InstancePathId.
    .DESCRIPTION
        Read-modify-write per device so an interrupted watch session (Ctrl+C)
        keeps everything captured so far. The file is the
        New-DefenderDcPolicy -AllowDeviceFile input format.
    .PARAMETER Path
        JSON file path. Created on first write.
    .PARAMETER Device
        A device record from ConvertTo-DcDevice.
    .EXAMPLE
        Add-DcDeviceRecord -Path .\approved.json -Device $device
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [pscustomobject] $Device
    )

    Set-StrictMode -Version Latest

    $existing = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $raw = Get-Content -LiteralPath $Path -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            # PS 5.1 ConvertFrom-Json emits a JSON array as ONE object (no
            # enumeration); ForEach-Object flattens a level so records
            # enumerate identically on 5.1 and 7+.
            try { $existing = @($raw | ConvertFrom-Json | ForEach-Object { $_ }) } catch {
                throw "Add-DcDeviceRecord: existing file is not valid JSON: $Path ($($_.Exception.Message))"
            }
        }
    }

    foreach ($e in $existing) {
        $prop = $e.PSObject.Properties['InstancePathId']
        if ($null -ne $prop -and [string]$prop.Value -eq [string]$Device.InstancePathId) { return }
    }

    $all = @($existing) + @($Device)
    # -InputObject (not pipeline) so a single element still serializes as [ ].
    $json = ConvertTo-Json -InputObject @($all) -Depth 5
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8
}
