#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    $libPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib/vbox.ps1"
    . $libPath
}

Describe "Find-VBoxManage" {
    BeforeEach {
        # Snapshot env vars so each test runs in isolation.
        $script:savedMsi = $env:VBOX_MSI_INSTALL_PATH
        $script:savedInstall = $env:VBOX_INSTALL_PATH
        $env:VBOX_MSI_INSTALL_PATH = $null
        $env:VBOX_INSTALL_PATH = $null
    }

    AfterEach {
        $env:VBOX_MSI_INSTALL_PATH = $script:savedMsi
        $env:VBOX_INSTALL_PATH = $script:savedInstall
    }

    It "returns null when no VBoxManage.exe is reachable" {
        Mock -CommandName Test-Path -MockWith { $false }
        Mock -CommandName Get-Command -MockWith { $null }

        Find-VBoxManage | Should -BeNullOrEmpty
    }

    It "prefers VBOX_MSI_INSTALL_PATH when set and present" {
        $msiPath = [System.IO.Path]::Combine($TestDrive, "msi-vbox")
        $expected = [System.IO.Path]::Combine($msiPath, "VBoxManage.exe")
        $env:VBOX_MSI_INSTALL_PATH = $msiPath

        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $expected } -MockWith { $true }
        Mock -CommandName Test-Path -MockWith { $false }

        Find-VBoxManage | Should -Be $expected
    }

    It "prefers VBOX_INSTALL_PATH over default Program Files when MSI var unset" {
        $altPath = [System.IO.Path]::Combine($TestDrive, "alt-vbox")
        $expected = [System.IO.Path]::Combine($altPath, "VBoxManage.exe")
        $env:VBOX_INSTALL_PATH = $altPath

        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $expected } -MockWith { $true }
        Mock -CommandName Test-Path -MockWith { $false }

        Find-VBoxManage | Should -Be $expected
    }

    It "falls back to Get-Command when no install path matches" {
        $shimPath = [System.IO.Path]::Combine($TestDrive, "shim", "VBoxManage.exe")
        Mock -CommandName Test-Path -MockWith { $false }
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq "VBoxManage.exe" } -MockWith {
            [PSCustomObject]@{ Source = $shimPath }
        }

        Find-VBoxManage | Should -Be $shimPath
    }
}
