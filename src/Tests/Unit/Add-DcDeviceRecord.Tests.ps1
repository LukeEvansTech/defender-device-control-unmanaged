BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\Add-DcDeviceRecord.ps1')

    function script:New-Record([string] $Id) {
        [pscustomobject]@{ FriendlyName = 'X'; Class = 'Usb'; InstancePathId = $Id }
    }
}

Describe 'Add-DcDeviceRecord' {
    It 'creates the file as a JSON array on first write' {
        $path = Join-Path $TestDrive 'a.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        $parsed = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
        $parsed.Count | Should -Be 1
        $parsed[0].InstancePathId | Should -Be 'USBSTOR\1'
    }

    It 'appends new devices and keeps existing ones' {
        $path = Join-Path $TestDrive 'b.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\2')
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count | Should -Be 2
    }

    It 'dedupes by InstancePathId' {
        $path = Join-Path $TestDrive 'c.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count | Should -Be 1
    }

    It 'single record still serializes as a JSON array (PS 5.1 unrolling guard)' {
        $path = Join-Path $TestDrive 'd.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        (Get-Content -LiteralPath $path -Raw).TrimStart() | Should -Match '^\['
    }

    It 'throws a clear error when the existing file is not valid JSON' {
        $path = Join-Path $TestDrive 'e.json'
        'not json' | Set-Content -LiteralPath $path
        { Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1') } |
            Should -Throw -ExpectedMessage '*not valid JSON*'
    }

    It 'file written after two appends contains two flat records (no nested arrays)' {
        $path = Join-Path $TestDrive 'flat.json'
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\1')
        Add-DcDeviceRecord -Path $path -Device (New-Record 'USBSTOR\2')
        $parsed = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | ForEach-Object { $_ })
        $parsed.Count | Should -Be 2
        foreach ($r in $parsed) {
            $r.PSObject.Properties['InstancePathId'] | Should -Not -BeNullOrEmpty
        }
    }
}
