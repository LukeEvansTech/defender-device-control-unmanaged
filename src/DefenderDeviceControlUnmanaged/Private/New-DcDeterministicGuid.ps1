function New-DcDeterministicGuid {
    <#
    .SYNOPSIS
        Derive a stable GUID from a seed string (UUIDv5-style).
    .DESCRIPTION
        SHA-1 of a fixed module namespace prefix + the seed, with the UUID
        version/variant bits set. The contract is determinism (same seed ->
        same GUID, forever), so generated policy XML is byte-identical across
        runs. RFC 4122 byte ordering is not required for that and is not
        attempted.
    .PARAMETER Seed
        Stable seed string, e.g. 'ddcu:rule:usb'.
    .EXAMPLE
        New-DcDeterministicGuid -Seed 'ddcu:group:approved'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Seed
    )

    Set-StrictMode -Version Latest

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("DefenderDeviceControlUnmanaged:$Seed"))
    } finally {
        $sha1.Dispose()
    }

    $bytes = $hash[0..15]
    # Data3 (bytes 6-7) is a little-endian short in Guid(byte[]); bytes[7] is
    # the high byte and therefore the first hex digit of the third group.
    $bytes[7] = [byte](($bytes[7] -band 0x0F) -bor 0x50)   # version 5
    $bytes[8] = [byte](($bytes[8] -band 0x3F) -bor 0x80)   # RFC 4122 variant

    '{' + ([guid]::new([byte[]]$bytes)).ToString() + '}'
}
