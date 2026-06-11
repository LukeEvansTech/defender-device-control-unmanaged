BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\DefenderDeviceControlUnmanaged\DefenderDeviceControlUnmanaged.psd1'
    Import-Module $ModuleManifest -Force
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
}

AfterAll {
    Remove-Module DefenderDeviceControlUnmanaged -Force -ErrorAction SilentlyContinue
}

Describe 'Test-DefenderDcPolicyXml' {

    BeforeAll {
        # Mock the engine-side validator so CI doesn't require MpCmdRun.exe.
        # The mock just no-ops, which simulates "engine validation passed".
        InModuleScope DefenderDeviceControlUnmanaged {
            Mock Test-DcXmlWithMpCmdRun {}
        }
    }

    It 'has -Path and -Kind parameters; -Kind ValidateSet Groups|Rules' {
        $cmd = Get-Command Test-DefenderDcPolicyXml
        $cmd.Parameters.ContainsKey('Path') | Should -BeTrue
        $cmd.Parameters.ContainsKey('Kind') | Should -BeTrue
        $kindVS = $cmd.Parameters['Kind'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $kindVS.ValidValues | Sort-Object | Should -Be @('Groups','Rules')
    }

    It 'returns boolean' {
        $cmd = Get-Command Test-DefenderDcPolicyXml
        $cmd.OutputType.Type | Should -Contain ([bool])
    }

    It 'returns $true on the good Groups fixture' {
        Test-DefenderDcPolicyXml -Path (Join-Path $Fixtures 'good-Groups.xml') -Kind Groups | Should -BeTrue
    }

    It 'returns $true on the good Rules fixture' {
        Test-DefenderDcPolicyXml -Path (Join-Path $Fixtures 'good-Rules.xml') -Kind Rules | Should -BeTrue
    }

    It 'supports skipping the engine-side validation layer' {
        $goodRulesPath = Join-Path $Fixtures 'good-Rules.xml'
        Test-DefenderDcPolicyXml -Path $goodRulesPath -Kind Rules -SkipEngineValidation | Should -BeTrue
        InModuleScope DefenderDeviceControlUnmanaged {
            Should -Invoke Test-DcXmlWithMpCmdRun -Times 0 -Exactly
        }
    }

    It 'fails with a BOM-specific error on bad-bom-Groups.xml' {
        $result = Test-DefenderDcPolicyXml -Path (Join-Path $Fixtures 'bad-bom-Groups.xml') -Kind Groups -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeFalse
        ($err -join ' ') | Should -Match 'BOM'
    }

    It 'fails with an xml-declaration-specific error on bad-xmldecl-Groups.xml' {
        $result = Test-DefenderDcPolicyXml -Path (Join-Path $Fixtures 'bad-xmldecl-Groups.xml') -Kind Groups -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeFalse
        ($err -join ' ') | Should -Match 'xml declaration|<\?xml'
    }

    It 'fails with a Name-attribute-specific error on bad-name-attr-Rules.xml' {
        $result = Test-DefenderDcPolicyXml -Path (Join-Path $Fixtures 'bad-name-attr-Rules.xml') -Kind Rules -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeFalse
        ($err -join ' ') | Should -Match 'Name.*attribute|Name.*child'
    }

    It 'fails with an Options-out-of-range error on bad-options-4-Rules.xml' {
        $result = Test-DefenderDcPolicyXml -Path (Join-Path $Fixtures 'bad-options-4-Rules.xml') -Kind Rules -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeFalse
        ($err -join ' ') | Should -Match 'Options.*[0-3]|Options.*bitmask|2-bit'
    }

    It 'fails when file does not exist' {
        $result = Test-DefenderDcPolicyXml -Path 'C:\does-not-exist.xml' -Kind Groups -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeFalse
        ($err -join ' ') | Should -Match 'not found'
    }

    It 'still rejects an empty-Entry-list PolicyRule under -SkipEngineValidation' {
        # Regression for the Codex P2: when MpCmdRun is skipped, the per-element
        # structural checks (every PolicyRule has at least one <Entry>, Id present)
        # must still run via Read-DcPolicyXml.
        $tmp = New-TemporaryFile
        $xml = '<PolicyRules><PolicyRule Id="{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}"><Name>empty</Name><IncludedIdList><GroupId>{x}</GroupId></IncludedIdList><ExcludedIdList/></PolicyRule></PolicyRules>'
        # Portable BOM-less UTF-8 write — Set-Content -Encoding utf8 emits a BOM
        # on Windows PowerShell 5.1, which would trip the BOM check before the
        # structural layer this test is targeting.
        [System.IO.File]::WriteAllText($tmp.FullName, $xml, [System.Text.UTF8Encoding]::new($false))
        try {
            $result = Test-DefenderDcPolicyXml -Path $tmp.FullName -Kind Rules -SkipEngineValidation -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeFalse
            ($err -join ' ') | Should -Match 'Entry|structural'
        }
        finally { Remove-Item $tmp.FullName -Force }
    }

    It 'has populated comment-based help (SYNOPSIS, DESCRIPTION, >=1 EXAMPLE)' {
        $help = Get-Help Test-DefenderDcPolicyXml -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.examples.example.Count | Should -BeGreaterThan 0
    }

    It 'returns false with a clear zero-rule message for an empty PolicyRules file (all-Allow case)' {
        $tmp = New-TemporaryFile
        [System.IO.File]::WriteAllText($tmp.FullName, '<PolicyRules></PolicyRules>', [System.Text.UTF8Encoding]::new($false))
        try {
            $result = Test-DefenderDcPolicyXml -Path $tmp.FullName -Kind Rules -SkipEngineValidation -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeFalse
            ($err -join ' ') | Should -Match 'zero.*PolicyRule|PolicyRule.*zero|all-Allow|Audit'
        }
        finally { Remove-Item $tmp.FullName -Force }
    }
}
