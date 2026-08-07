#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures Whonix Gateway and Workstation VMs with optimal resources and security hardening.
.DESCRIPTION
    Dynamically allocates RAM/CPU based on host specs, sets up networking
    (NAT + internal for Gateway, internal-only for Workstation), and applies
    VirtualBox security hardening: clipboard isolation, no shared folders,
    no USB passthrough, audio disabled, 3D acceleration disabled.
.EXAMPLE
    .\configure-vms.ps1
#>

[CmdletBinding()]
param(
    [string]$GatewayVMName = "",
    [string]$WorkstationVMName = "",
    [string]$InternalNetworkName = "Whonix"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path (Join-Path $PSScriptRoot "lib") "logging.ps1")
. (Join-Path (Join-Path $PSScriptRoot "lib") "vbox.ps1")
. (Join-Path (Join-Path $PSScriptRoot "lib") "allocation.ps1")

# ============================================================
# Helper: Run VBoxManage command with logging
# ============================================================
function Invoke-VBoxManage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [string]$Description = ""
    )

    if ($Description) { Write-Log "  $Description" -Level DEBUG }

    $output = & $VBoxManage $Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errorText = $output | Out-String
        Write-Log "  VBoxManage error: $errorText" -Level ERROR
        throw "VBoxManage command failed: $Arguments"
    }
    return $output
}

# ============================================================
# Get a VM to powered off, whatever state it starts in
# ============================================================
function Stop-VmForConfiguration {
    <#
    .SYNOPSIS
        Brings a VM to powered off so modifyvm will take.
    .DESCRIPTION
        modifyvm needs a VM that is not executing. Getting there is not always
        a poweroff: controlvm poweroff itself needs a VM that IS executing, so
        on a saved VM it errors out. A saved VM gets to powered off by having
        its saved state discarded. Resolve-VmPowerOffAction holds that table.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [string]$VMName,
        [Parameter(Mandatory)] [string]$Label
    )

    $vmInfo = Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @("showvminfo", $VMName, "--machinereadable") -Description "Reading VM state"
    if (-not (($vmInfo | Out-String) -match 'VMState="([^"]+)"')) {
        throw "Could not read the state of $Label VM '$VMName'. Refusing to reconfigure a VM whose state is unknown."
    }
    $state = $Matches[1]

    switch (Resolve-VmPowerOffAction -VmState $state) {
        'none' {
            Write-Log "$Label VM is already powered off." -Level DEBUG
        }
        'poweroff' {
            Write-Log "$Label VM is $state. Powering off..." -Level WARN
            Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @("controlvm", $VMName, "poweroff") -Description "Powering off $Label"
            Start-Sleep -Seconds 3
        }
        'discardstate' {
            # Discarding is the only route from saved to poweroff, and it throws
            # the guest session away. Worth saying out loud rather than doing
            # quietly, because the user may not expect to lose it.
            Write-Log "$Label VM is $state. Discarding its saved state so it can be reconfigured..." -Level WARN
            Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @("discardstate", $VMName) -Description "Discarding saved state for $Label"
            Start-Sleep -Seconds 3
        }
        'unsupported' {
            throw "$Label VM '$VMName' is in state '$state', which cannot be brought to powered off from here. Wait for it to settle, then rerun."
        }
    }
}

# ============================================================
# Calculate resource allocation
# ============================================================
function Get-ResourceAllocation {
    Write-Banner "Detecting System Resources"

    $totalRamBytes = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
    $totalRamMB = [math]::Floor($totalRamBytes / 1MB)
    $totalRamGB = [math]::Round($totalRamBytes / 1GB, 1)

    $cpuCores = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

    Write-Log "Total RAM: $totalRamGB GB ($totalRamMB MB)"
    Write-Log "Total CPU cores: $cpuCores"

    # The sizing math lives in lib/allocation.ps1 so it can be tested without
    # a real host or VirtualBox. See Get-VmResourceAllocation.
    $allocation = Get-VmResourceAllocation -TotalRamBytes $totalRamBytes -CpuCores $cpuCores

    Write-Log "Resource allocation plan:" -Level INFO
    Write-Log "  Gateway:     $($allocation.GatewayCores) core(s), $($allocation.GatewayRamMB) MB RAM" -Level INFO
    Write-Log "  Workstation: $($allocation.WorkstationCores) core(s), $($allocation.WorkstationRamMB) MB RAM" -Level INFO
    Write-Log "  Host reserve: ~4096 MB RAM, 1 core" -Level INFO

    return $allocation
}

# ============================================================
# Configure Gateway VM
# ============================================================
function Set-GatewayConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [hashtable]$Allocation
    )

    Write-Banner "Configuring Whonix Gateway"

    $vmName = $GatewayVMName

    # Ensure VM is powered off
    Stop-VmForConfiguration -VBoxManage $VBoxManage -VMName $vmName -Label "Gateway"

    # CPU and RAM
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $vmName,
        "--cpus", $Allocation.GatewayCores.ToString(),
        "--memory", $Allocation.GatewayRamMB.ToString()
    ) -Description "Setting CPU ($($Allocation.GatewayCores)) and RAM ($($Allocation.GatewayRamMB) MB)"

    # Network: Adapter 1 = NAT, Adapter 2 = Internal Network "Whonix"
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $vmName,
        "--nic1", "nat",
        "--nic2", "intnet",
        "--intnet2", $InternalNetworkName
    ) -Description "Setting network adapters (NAT + Internal '$InternalNetworkName')"

    # Security hardening
    Set-SecurityHardening -VBoxManage $VBoxManage -VMName $vmName

    Write-Log "Gateway configuration complete." -Level SUCCESS
}

# ============================================================
# Configure Workstation VM
# ============================================================
function Set-WorkstationConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [hashtable]$Allocation
    )

    Write-Banner "Configuring Whonix Workstation"

    $vmName = $WorkstationVMName

    # Ensure VM is powered off
    Stop-VmForConfiguration -VBoxManage $VBoxManage -VMName $vmName -Label "Workstation"

    # CPU and RAM
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $vmName,
        "--cpus", $Allocation.WorkstationCores.ToString(),
        "--memory", $Allocation.WorkstationRamMB.ToString()
    ) -Description "Setting CPU ($($Allocation.WorkstationCores)) and RAM ($($Allocation.WorkstationRamMB) MB)"

    # Network: Adapter 1 = Internal Network "Whonix" ONLY (no NAT, no internet bypass)
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $vmName,
        "--nic1", "intnet",
        "--intnet1", $InternalNetworkName,
        "--nic2", "none"
    ) -Description "Setting network adapter (Internal '$InternalNetworkName' only)"

    # Security hardening
    Set-SecurityHardening -VBoxManage $VBoxManage -VMName $vmName

    Write-Log "Workstation configuration complete." -Level SUCCESS
}

# ============================================================
# Security hardening (applied to both VMs)
# ============================================================
function Set-SecurityHardening {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [string]$VMName
    )

    Write-Log "Applying security hardening to $VMName..." -Level INFO

    # Disable clipboard sharing
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $VMName, "--clipboard-mode", "disabled"
    ) -Description "Disabling clipboard sharing"

    # Disable drag-and-drop
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $VMName, "--drag-and-drop", "disabled"
    ) -Description "Disabling drag-and-drop"

    # Disable shared folders (remove any that exist)
    try {
        $sfOutput = Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @("showvminfo", $VMName, "--machinereadable")
        $sharedFolders = $sfOutput | Select-String -Pattern 'SharedFolderNameMachineMapping\d+="([^"]+)"'
        foreach ($sf in $sharedFolders) {
            $folderName = $sf.Matches[0].Groups[1].Value
            Write-Log "  Removing shared folder: $folderName" -Level WARN
            Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
                "sharedfolder", "remove", $VMName, "--name", $folderName
            )
        }
    }
    catch {
        Write-Log "  No shared folders to remove." -Level DEBUG
    }

    # Disable USB controllers
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $VMName, "--usb", "off"
    ) -Description "Disabling USB 1.1"

    try {
        Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
            "modifyvm", $VMName, "--usbehci", "off"
        ) -Description "Disabling USB 2.0 (EHCI)"
    }
    catch { Write-Log "  USB 2.0 controller not present, skipping." -Level DEBUG }

    try {
        Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
            "modifyvm", $VMName, "--usbxhci", "off"
        ) -Description "Disabling USB 3.0 (xHCI)"
    }
    catch { Write-Log "  USB 3.0 controller not present, skipping." -Level DEBUG }

    # Disable audio
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $VMName, "--audio-enabled", "off"
    ) -Description "Disabling audio"

    # Disable 3D acceleration
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $VMName, "--graphicscontroller", "vmsvga",
        "--accelerate3d", "off"
    ) -Description "Disabling 3D acceleration (VMSVGA)"

    # Enable nested paging for performance + security
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $VMName, "--nested-hw-virt", "off",
        "--largepages", "on"
    ) -Description "Enabling large pages, disabling nested HW virtualization"

    # Disable remote desktop
    Invoke-VBoxManage -VBoxManage $VBoxManage -Arguments @(
        "modifyvm", $VMName, "--vrde", "off"
    ) -Description "Disabling VRDE (remote desktop)"

    Write-Log "Security hardening applied to $VMName." -Level SUCCESS
}

# ============================================================
# Main Execution
# ============================================================
try {
    Write-Banner "WhonixAutoSetup - VM Configuration"

    $vboxManage = Find-VBoxManage
    if (-not $vboxManage) {
        throw "VBoxManage.exe not found. Run setup.ps1 first to install VirtualBox."
    }
    Write-Log "Using VBoxManage: $vboxManage"

    # Auto-detect VM names if not specified
    $vmList = & $vboxManage list vms 2>&1 | Out-String
    if ([string]::IsNullOrEmpty($GatewayVMName)) {
        $GatewayVMName = Resolve-WhonixVmName -VmListOutput $vmList -NamePrefix "Whonix-Gateway"
        if (-not $GatewayVMName) { throw "No Whonix Gateway VM found. Run setup.ps1 first." }
    }
    if ([string]::IsNullOrEmpty($WorkstationVMName)) {
        $WorkstationVMName = Resolve-WhonixVmName -VmListOutput $vmList -NamePrefix "Whonix-Workstation"
        if (-not $WorkstationVMName) { throw "No Whonix Workstation VM found. Run setup.ps1 first." }
    }
    Write-Log "Detected Gateway VM:     $GatewayVMName"
    Write-Log "Detected Workstation VM: $WorkstationVMName"

    $allocation = Get-ResourceAllocation

    Set-GatewayConfiguration -VBoxManage $vboxManage -Allocation $allocation
    Set-WorkstationConfiguration -VBoxManage $vboxManage -Allocation $allocation

    Write-Banner "Configuration Complete"
    Write-Log "Both VMs are configured and hardened." -Level SUCCESS
    Write-Log "Next step: Run .\start-whonix.ps1 to launch the VMs."
    Write-Log "Log file: $(Get-LogFilePath)"
}
catch {
    Write-Log "CONFIGURATION FAILED: $_" -Level ERROR
    Write-Log "Check the log file for details: $(Get-LogFilePath)" -Level ERROR
    exit 1
}
