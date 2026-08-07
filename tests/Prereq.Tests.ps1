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

Describe "Test-VirtualizationFirmwareEnabled" {
    Context "single socket" {
        It "passes when the one socket reports enabled" {
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($true) | Should -BeTrue
        }

        It "fails when the one socket reports disabled" {
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($false) | Should -BeFalse
        }
    }

    Context "multiple sockets" {
        It "fails when every socket reports disabled" {
            # The bug this targets. Win32_Processor returns one object per
            # socket, so reading the property off the collection hands back
            # @($false, $false), and PowerShell calls any two element array
            # true. A dual socket box with VT-x off in firmware used to pass.
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($false, $false) |
                Should -BeFalse
        }

        It "passes when every socket reports enabled" {
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($true, $true) |
                Should -BeTrue
        }

        It "fails when only some sockets report enabled" {
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($true, $false) |
                Should -BeFalse
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($false, $true) |
                Should -BeFalse
        }

        It "handles a four socket host" {
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($true, $true, $true, $true) |
                Should -BeTrue
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($true, $true, $false, $true) |
                Should -BeFalse
        }
    }

    Context "missing or unreadable data" {
        It "fails on an empty collection rather than assuming enabled" {
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @() | Should -BeFalse
        }

        It "fails on null" {
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues $null | Should -BeFalse
        }

        It "fails when a socket reports null, which is not a yes" {
            # WMI leaves the property null on hardware that does not report it.
            Test-VirtualizationFirmwareEnabled -FirmwareEnabledValues @($true, $null) |
                Should -BeFalse
        }
    }
}
