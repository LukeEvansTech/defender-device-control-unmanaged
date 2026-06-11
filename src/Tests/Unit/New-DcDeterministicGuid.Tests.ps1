BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\New-DcDeterministicGuid.ps1')
}

Describe 'New-DcDeterministicGuid' {
    It 'returns a braced GUID string' {
        New-DcDeterministicGuid -Seed 'ddcu:rule:usb' |
            Should -Match '^\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$'
    }

    It 'is deterministic: same seed, same GUID' {
        $a = New-DcDeterministicGuid -Seed 'ddcu:group:approved'
        $b = New-DcDeterministicGuid -Seed 'ddcu:group:approved'
        $a | Should -Be $b
    }

    It 'different seeds produce different GUIDs' {
        (New-DcDeterministicGuid -Seed 'ddcu:rule:usb') |
            Should -Not -Be (New-DcDeterministicGuid -Seed 'ddcu:rule:wpd')
    }

    It 'does not collide with the shipped starter XML GUIDs' {
        $starter = @(
            '{18c18655-7803-4235-a811-3da676a1f197}',
            '{b9854cf9-b7e3-4155-b0ec-5031d44657b3}',
            '{c145b8d2-2799-469b-8014-927e7dd9babf}',
            '{77d21842-eba0-44a7-a46a-1c0291b087e0}',
            '{d1a03385-6742-4f39-b05f-7f7f5c5bee1e}',
            '{f3c3878f-3133-4b5a-83e8-4b4b79c35591}'
        )
        foreach ($seed in 'ddcu:group:usb','ddcu:group:wpd','ddcu:group:optical','ddcu:group:approved','ddcu:rule:usb','ddcu:rule:wpd','ddcu:rule:optical') {
            $starter | Should -Not -Contain (New-DcDeterministicGuid -Seed $seed)
        }
    }

    It 'throws on an empty seed' {
        { New-DcDeterministicGuid -Seed '' } | Should -Throw
    }
}
