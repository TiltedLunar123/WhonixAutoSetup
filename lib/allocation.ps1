#Requires -Version 5.1
<#
.SYNOPSIS
    Pure resource-allocation math for WhonixAutoSetup.
.DESCRIPTION
    Decides how much RAM and how many CPU cores to give the Whonix Gateway
    and Workstation VMs, given the host's total RAM and logical core count.
    Kept free of CIM calls, logging, and VirtualBox so it can be unit-tested
    without a real machine. Dot-source this from configure-vms.ps1.
#>

function Get-VmResourceAllocation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [long]$TotalRamBytes,
        [Parameter(Mandatory)] [int]$CpuCores
    )

    $totalRamMB = [math]::Floor($TotalRamBytes / 1MB)
    $totalRamGB = [math]::Round($TotalRamBytes / 1GB, 1)

    # Gateway is fixed: 1 core, 1024 MB. It only proxies Tor.
    $gwCores = 1
    $gwRamMB = 1024

    # Reserve room for the host OS plus the gateway before sizing the workstation.
    $hostReserveMB = 4096
    $availableRamMB = $totalRamMB - $hostReserveMB - $gwRamMB
    $availableCores = $CpuCores - $gwCores - 1  # leave 1 core for the host
    if ($availableCores -lt 1) { $availableCores = 1 }

    # Give the workstation a bigger slice on roomier hosts.
    if ($totalRamGB -ge 32) {
        $wsRamMB = [math]::Floor($availableRamMB * 0.40)
        $wsCores = [math]::Min($availableCores, 4)
    }
    elseif ($totalRamGB -ge 16) {
        $wsRamMB = [math]::Floor($availableRamMB * 0.33)
        $wsCores = [math]::Min($availableCores, 3)
    }
    else {
        $wsRamMB = [math]::Floor($availableRamMB * 0.25)
        $wsCores = [math]::Min($availableCores, 2)
    }

    # Floor at 2048 MB, round down to a 128 MB step, cap at 8192 MB.
    if ($wsRamMB -lt 2048) { $wsRamMB = 2048 }
    $wsRamMB = [math]::Floor($wsRamMB / 128) * 128
    if ($wsRamMB -gt 8192) { $wsRamMB = 8192 }
    if ($wsCores -gt 4) { $wsCores = 4 }

    return @{
        GatewayCores     = $gwCores
        GatewayRamMB     = $gwRamMB
        WorkstationCores = $wsCores
        WorkstationRamMB = $wsRamMB
    }
}
