#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    $libPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib/prereq.ps1"
    . $libPath
}

Describe "Test-ResourceThreshold" {
    Context "RAM rounding (8 GB minimum)" {
        It "passes for exactly 8 GB" {
            $bytes = [long](8 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 8 | Should -BeTrue
        }

        It "passes for 7.9 GB (the bug this fix targets)" {
            $bytes = [long](7.9 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 8 | Should -BeTrue
        }

        It "passes for 7.8 GB (within the 256 MB slack)" {
            $bytes = [long](7.8 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 8 | Should -BeTrue
        }

        It "fails for 7.6 GB (slack exhausted)" {
            $bytes = [long](7.6 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 8 | Should -BeFalse
        }

        It "fails for 4 GB" {
            $bytes = [long](4 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 8 | Should -BeFalse
        }
    }

    Context "Disk rounding (50 GB minimum)" {
        It "passes for exactly 50 GB free" {
            $bytes = [long](50 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 50 | Should -BeTrue
        }

        It "passes for 49.9 GB free" {
            $bytes = [long](49.9 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 50 | Should -BeTrue
        }

        It "fails for 49.5 GB free" {
            $bytes = [long](49.5 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 50 | Should -BeFalse
        }
    }

    Context "Slack override" {
        It "honors a custom slack of 0 MB (strict comparison)" {
            $bytes = [long](7.99 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 8 -SlackMB 0 | Should -BeFalse
        }

        It "honors a wider slack of 1024 MB" {
            $bytes = [long](7.0 * 1GB)
            Test-ResourceThreshold -ActualBytes $bytes -MinimumGB 8 -SlackMB 1024 | Should -BeTrue
        }
    }
}
