#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    $libPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib/logging.ps1"
    . $libPath

    # Redirect the module's log file into the test sandbox so assertions read
    # a known path and nothing lands in the repo's logs/ directory.
    $script:LogFile = Join-Path $TestDrive "test-run.log"
}

Describe "Get-LogFilePath" {
    It "returns the active log file path" {
        Get-LogFilePath | Should -Be $script:LogFile
    }
}

Describe "Write-Log" {
    BeforeEach {
        if (Test-Path $script:LogFile) { Remove-Item $script:LogFile -Force }
    }

    It "appends the message to the log file" {
        Write-Log "hello world"
        $script:LogFile | Should -FileContentMatch "hello world"
    }

    It "tags entries with INFO by default" {
        Write-Log "default level"
        Get-Content $script:LogFile -Raw | Should -Match "\[INFO\] default level"
    }

    It "tags entries with the level that was passed" {
        Write-Log "boom" -Level ERROR
        Get-Content $script:LogFile -Raw | Should -Match "\[ERROR\] boom"
    }

    It "writes a timestamp in front of every entry" {
        Write-Log "stamped"
        Get-Content $script:LogFile -Raw |
            Should -Match "^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] stamped"
    }

    It "rejects a level outside the allowed set" {
        { Write-Log "nope" -Level TRACE } | Should -Throw
    }

    It "appends rather than overwriting across calls" {
        Write-Log "first"
        Write-Log "second"
        $lines = @(Get-Content $script:LogFile | Where-Object { $_ -match '\[INFO\]' })
        $lines.Count | Should -Be 2
    }
}

Describe "Write-Banner" {
    BeforeEach {
        if (Test-Path $script:LogFile) { Remove-Item $script:LogFile -Force }
    }

    It "writes the title into the log file" {
        Write-Banner "My Section"
        $script:LogFile | Should -FileContentMatch "My Section"
    }

    It "writes a 60-character border around the title" {
        Write-Banner "Bordered"
        Get-Content $script:LogFile -Raw | Should -Match ("=" * 60)
    }
}
