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

    It "finds VBoxManage at the default Program Files path when no env vars are set" {
        # The common case: a stock VirtualBox install, no VBOX_* vars, binary
        # sitting under 64-bit Program Files.
        $expected = Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe"
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $expected } -MockWith { $true }
        Mock -CommandName Test-Path -MockWith { $false }

        Find-VBoxManage | Should -Be $expected
    }

    It "falls back to the 32-bit Program Files path when the 64-bit path is absent" {
        $x86 = Join-Path ${env:ProgramFiles(x86)} "Oracle\VirtualBox\VBoxManage.exe"
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $x86 } -MockWith { $true }
        Mock -CommandName Test-Path -MockWith { $false }

        Find-VBoxManage | Should -Be $x86
    }

    It "lets an explicit VBOX_INSTALL_PATH override win when both env vars are set" {
        # The README tells people to set VBOX_INSTALL_PATH when the binary lives
        # somewhere unusual, so that explicit override should beat the MSI var even
        # when both point at a real binary.
        $msiPath = [System.IO.Path]::Combine($TestDrive, "msi-vbox")
        $installPath = [System.IO.Path]::Combine($TestDrive, "explicit-vbox")
        $env:VBOX_MSI_INSTALL_PATH = $msiPath
        $env:VBOX_INSTALL_PATH = $installPath
        $expected = [System.IO.Path]::Combine($installPath, "VBoxManage.exe")
        $msiExe = [System.IO.Path]::Combine($msiPath, "VBoxManage.exe")

        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $expected -or $Path -eq $msiExe } -MockWith { $true }
        Mock -CommandName Test-Path -MockWith { $false }

        Find-VBoxManage | Should -Be $expected
    }
}

Describe "Resolve-WhonixVmName" {
    # A typical `VBoxManage list vms` listing prints one VM per line: "Name" {uuid}.
    It "finds the Gateway by prefix" {
        $listing = @'
"Whonix-Gateway-Xfce" {11111111-1111-1111-1111-111111111111}
"Whonix-Workstation-Xfce" {22222222-2222-2222-2222-222222222222}
'@
        Resolve-WhonixVmName -VmListOutput $listing -NamePrefix "Whonix-Gateway" |
            Should -Be "Whonix-Gateway-Xfce"
    }

    It "finds the Workstation by prefix" {
        $listing = @'
"Whonix-Gateway-Xfce" {11111111-1111-1111-1111-111111111111}
"Whonix-Workstation-Xfce" {22222222-2222-2222-2222-222222222222}
'@
        Resolve-WhonixVmName -VmListOutput $listing -NamePrefix "Whonix-Workstation" |
            Should -Be "Whonix-Workstation-Xfce"
    }

    It "does not return a Workstation when asked for a Gateway" {
        $wsOnly = '"Whonix-Workstation-Xfce" {22222222-2222-2222-2222-222222222222}'
        Resolve-WhonixVmName -VmListOutput $wsOnly -NamePrefix "Whonix-Gateway" |
            Should -BeNullOrEmpty
    }

    It "returns null when nothing matches the prefix" {
        $other = '"Some-Other-VM" {33333333-3333-3333-3333-333333333333}'
        Resolve-WhonixVmName -VmListOutput $other -NamePrefix "Whonix-Gateway" |
            Should -BeNullOrEmpty
    }

    It "returns null on empty listing output" {
        Resolve-WhonixVmName -VmListOutput "" -NamePrefix "Whonix-Gateway" |
            Should -BeNullOrEmpty
    }

    It "picks the canonical VM over a longer clone regardless of order" {
        $withClone = @'
"Whonix-Gateway-Xfce Clone" {aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}
"Whonix-Gateway-Xfce" {11111111-1111-1111-1111-111111111111}
'@
        Resolve-WhonixVmName -VmListOutput $withClone -NamePrefix "Whonix-Gateway" |
            Should -Be "Whonix-Gateway-Xfce"

        # Same answer if VirtualBox happens to list the clone second.
        $cloneSecond = @'
"Whonix-Gateway-Xfce" {11111111-1111-1111-1111-111111111111}
"Whonix-Gateway-Xfce Clone" {aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}
'@
        Resolve-WhonixVmName -VmListOutput $cloneSecond -NamePrefix "Whonix-Gateway" |
            Should -Be "Whonix-Gateway-Xfce"
    }

    It "prefers an exact prefix match over a longer suffixed name" {
        $exactAndLong = @'
"Whonix-Gateway-Xfce" {11111111-1111-1111-1111-111111111111}
"Whonix-Gateway" {44444444-4444-4444-4444-444444444444}
'@
        Resolve-WhonixVmName -VmListOutput $exactAndLong -NamePrefix "Whonix-Gateway" |
            Should -Be "Whonix-Gateway"
    }

    It "matches case-sensitively, so a lowercase prefix finds nothing" {
        # The match uses an Ordinal (case-sensitive) StartsWith on purpose, so a
        # miscased prefix must not silently resolve to the real VM.
        $listing = '"Whonix-Gateway-Xfce" {11111111-1111-1111-1111-111111111111}'
        Resolve-WhonixVmName -VmListOutput $listing -NamePrefix "whonix-gateway" |
            Should -BeNullOrEmpty
    }
}

Describe "Resolve-VmStartAction" {
    It "reports nothing to do for a running VM" {
        Resolve-VmStartAction -VmState 'running' | Should -Be 'none'
    }

    It "resumes a paused VM" {
        Resolve-VmStartAction -VmState 'paused' | Should -Be 'resume'
    }

    It "restores a saved VM rather than resuming it" {
        # This is the case that used to break. Closing the Whonix window with
        # "save the machine state" leaves VMState=saved, and controlvm resume
        # only works on a paused VM, so the launch died there. startvm is what
        # brings a saved VM back.
        Resolve-VmStartAction -VmState 'saved' | Should -Be 'restore'
    }

    It "restores an aborted-saved VM, since the saved state outlived the process" {
        Resolve-VmStartAction -VmState 'aborted-saved' | Should -Be 'restore'
    }

    It "cold boots a powered off VM" {
        Resolve-VmStartAction -VmState 'poweroff' | Should -Be 'start'
    }

    It "cold boots an aborted VM, which has no saved state to restore" {
        Resolve-VmStartAction -VmState 'aborted' | Should -Be 'start'
    }

    It "refuses to guess at a VM that is mid-transition" {
        foreach ($state in @('starting', 'stopping', 'saving', 'restoring', 'settingup')) {
            Resolve-VmStartAction -VmState $state | Should -Be 'unsupported' -Because "$state is transient"
        }
    }

    It "refuses to start a wedged VM, which has to be powered off first" {
        Resolve-VmStartAction -VmState 'stuck' | Should -Be 'unsupported'
    }

    It "treats an unreadable state as unsupported instead of assuming it is off" {
        # Get-VMState hands back "unknown" when the VMState line is missing.
        Resolve-VmStartAction -VmState 'unknown' | Should -Be 'unsupported'
        Resolve-VmStartAction -VmState '' | Should -Be 'unsupported'
    }

    It "tolerates the casing and padding VirtualBox might report" {
        Resolve-VmStartAction -VmState ' Saved ' | Should -Be 'restore'
        Resolve-VmStartAction -VmState 'RUNNING' | Should -Be 'none'
    }
}

Describe "Resolve-VmPowerOffAction" {
    It "reports nothing to do for a VM that is already off" {
        Resolve-VmPowerOffAction -VmState 'poweroff' | Should -Be 'none'
    }

    It "leaves an aborted VM alone, since the process is already gone" {
        Resolve-VmPowerOffAction -VmState 'aborted' | Should -Be 'none'
    }

    It "powers off a running VM" {
        Resolve-VmPowerOffAction -VmState 'running' | Should -Be 'poweroff'
    }

    It "powers off a paused VM" {
        Resolve-VmPowerOffAction -VmState 'paused' | Should -Be 'poweroff'
    }

    It "powers off a wedged VM" {
        Resolve-VmPowerOffAction -VmState 'stuck' | Should -Be 'poweroff'
    }

    It "discards the saved state of a saved VM instead of powering it off" {
        # The other half of the same bug. configure-vms.ps1 wants the VM at
        # poweroff so modifyvm will take, and controlvm poweroff errors on a VM
        # that is not executing.
        Resolve-VmPowerOffAction -VmState 'saved' | Should -Be 'discardstate'
    }

    It "discards the saved state of an aborted-saved VM" {
        Resolve-VmPowerOffAction -VmState 'aborted-saved' | Should -Be 'discardstate'
    }

    It "refuses to guess at a VM that is mid-transition" {
        foreach ($state in @('starting', 'stopping', 'saving', 'restoring', 'settingup')) {
            Resolve-VmPowerOffAction -VmState $state | Should -Be 'unsupported' -Because "$state is transient"
        }
    }

    It "treats an unreadable state as unsupported instead of assuming it is off" {
        Resolve-VmPowerOffAction -VmState 'unknown' | Should -Be 'unsupported'
        Resolve-VmPowerOffAction -VmState '' | Should -Be 'unsupported'
    }

    It "tolerates the casing and padding VirtualBox might report" {
        Resolve-VmPowerOffAction -VmState ' Saved ' | Should -Be 'discardstate'
        Resolve-VmPowerOffAction -VmState 'POWEROFF' | Should -Be 'none'
    }
}
