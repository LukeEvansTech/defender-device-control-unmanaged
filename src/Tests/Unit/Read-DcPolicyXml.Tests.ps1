BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged'
    . (Join-Path $ModuleRoot 'Private\Read-DcPolicyXml.ps1')
    $script:PolicyDir = Join-Path $ModuleRoot 'policy'
}

Describe 'Read-DcPolicyXml' {
    It 'returns three Group records from PolicyGroups.xml' {
        $items = Read-DcPolicyXml -Path (Join-Path $PolicyDir 'PolicyGroups.xml')
        @($items).Count | Should -Be 3
        $items | ForEach-Object { $_.Kind | Should -Be 'Group' }
    }

    It 'returns three Rule records from PolicyRules.Enforce.xml' {
        $items = Read-DcPolicyXml -Path (Join-Path $PolicyDir 'PolicyRules.Enforce.xml')
        @($items).Count | Should -Be 3
        $items | ForEach-Object { $_.Kind | Should -Be 'Rule' }
    }

    It 'extracts the Group GUIDs from PolicyGroups.xml' {
        $items = Read-DcPolicyXml -Path (Join-Path $PolicyDir 'PolicyGroups.xml')
        $items.Id | Should -Contain '{18c18655-7803-4235-a811-3da676a1f197}'
        $items.Id | Should -Contain '{b9854cf9-b7e3-4155-b0ec-5031d44657b3}'
        $items.Id | Should -Contain '{c145b8d2-2799-469b-8014-927e7dd9babf}'
    }

    It 'RawXml round-trips: re-parsing it yields the same Id' {
        $items = Read-DcPolicyXml -Path (Join-Path $PolicyDir 'PolicyGroups.xml')
        foreach ($i in $items) {
            ([xml]$i.RawXml).Group.Id | Should -Be $i.Id
        }
    }

    It 'throws on a missing file' {
        { Read-DcPolicyXml -Path 'C:\does\not\exist.xml' } | Should -Throw
    }

    It 'throws on malformed XML' {
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value '<Groups><Group Id="not-closed>' -Encoding utf8
        try { { Read-DcPolicyXml -Path $tmp.FullName } | Should -Throw }
        finally { Remove-Item $tmp.FullName -Force }
    }

    It 'throws when a Group is missing an Id attribute' {
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value '<Groups><Group Type="Device"><Name>x</Name></Group></Groups>' -Encoding utf8
        try { { Read-DcPolicyXml -Path $tmp.FullName } | Should -Throw -ExpectedMessage '*Id*' }
        finally { Remove-Item $tmp.FullName -Force }
    }

    It 'throws when a PolicyRule has zero Entry elements' {
        $tmp = New-TemporaryFile
        Set-Content -LiteralPath $tmp.FullName -Value '<PolicyRules><PolicyRule Id="{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}" Name="empty"><IncludedIdList><GroupId>{x}</GroupId></IncludedIdList><ExcludedIdList/></PolicyRule></PolicyRules>' -Encoding utf8
        try { { Read-DcPolicyXml -Path $tmp.FullName } | Should -Throw -ExpectedMessage '*Entry*' }
        finally { Remove-Item $tmp.FullName -Force }
    }

    It 'extracts EntryTypes from <Type> child elements of <Entry>' {
        $items = Read-DcPolicyXml -Path (Join-Path $PolicyDir 'PolicyRules.Enforce.xml')
        # The shipped Enforce fixture has Deny + AuditDenied entries per rule;
        # Audit-build fixtures use AuditAllowed. Either way EntryTypes must be
        # populated (this catches the .Attributes['Type'] regression).
        foreach ($i in $items) {
            $i.EntryTypes | Should -Not -BeNullOrEmpty
            $i.EntryTypes | ForEach-Object { $_ | Should -BeOfType [string] }
            $i.EntryTypes | ForEach-Object { $_ | Should -Match '^(Deny|AuditDenied|AuditAllowed|Allow)$' }
        }
        # The Enforce starter must contain at least one Deny across all rules.
        ($items | ForEach-Object { $_.EntryTypes }) -contains 'Deny' | Should -BeTrue
    }

    It 'returns empty (no throw) for an empty PolicyRules root element' {
        $tmp = New-TemporaryFile
        [System.IO.File]::WriteAllText($tmp.FullName, '<PolicyRules></PolicyRules>', [System.Text.UTF8Encoding]::new($false))
        try {
            { Read-DcPolicyXml -Path $tmp.FullName } | Should -Not -Throw
            $items = Read-DcPolicyXml -Path $tmp.FullName
            @($items).Count | Should -Be 0
        }
        finally { Remove-Item $tmp.FullName -Force }
    }

    It 'returns empty (no throw) for an empty Groups root element' {
        $tmp = New-TemporaryFile
        [System.IO.File]::WriteAllText($tmp.FullName, '<Groups></Groups>', [System.Text.UTF8Encoding]::new($false))
        try {
            { Read-DcPolicyXml -Path $tmp.FullName } | Should -Not -Throw
            $items = Read-DcPolicyXml -Path $tmp.FullName
            @($items).Count | Should -Be 0
        }
        finally { Remove-Item $tmp.FullName -Force }
    }
}
