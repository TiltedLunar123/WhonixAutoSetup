#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Validates system prerequisites for Whonix VM deployment.
.DESCRIPTION
    Checks total RAM, CPU cores, free disk space, and hardware virtualization
    support. Outputs a pass/fail report and exits non-zero if minimums are not met.
.EXAMPLE
    .\prereq-check.ps1
    .\prereq-check.ps1 -MinRamGB 16 -MinCores 6 -MinDiskGB 80
#>

[CmdletBinding()]
param(
    [int]$MinRamGB = 8,
    [int]$MinCores = 4,
    [int]$MinDiskGB = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path (Join-Path $PSScriptRoot "lib") "logging.ps1")
. (Join-Path (Join-Path $PSScriptRoot "lib") "prereq.ps1")

Write-Banner "WhonixAutoSetup - Prerequisite Check"
Write-Log "Starting system prerequisite validation..."

$results = @()
$allPassed = $true

# --- RAM Check ---
try {
    $totalRamBytes = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
    $totalRamGB = [math]::Round($totalRamBytes / 1GB, 1)
    $ramPassed = Test-ResourceThreshold -ActualBytes $totalRamBytes -MinimumGB $MinRamGB
    if (-not $ramPassed) { $allPassed = $false }

    $results += [PSCustomObject]@{
        Check    = "Total RAM"
        Detected = "$totalRamGB GB"
        Required = "$MinRamGB GB"
        Status   = if ($ramPassed) { "PASS" } else { "FAIL" }
    }
    Write-Log "RAM: $totalRamGB GB detected (minimum: $MinRamGB GB) - $(if ($ramPassed) {'PASS'} else {'FAIL'})" `
        -Level $(if ($ramPassed) {"SUCCESS"} else {"ERROR"})
}
catch {
    $allPassed = $false
    $results += [PSCustomObject]@{
        Check    = "Total RAM"
        Detected = "Error"
        Required = "$MinRamGB GB"
        Status   = "FAIL"
    }
    Write-Log "Failed to detect RAM: $_" -Level ERROR
}

# --- CPU Cores Check ---
try {
    $cpuCores = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $coresPassed = $cpuCores -ge $MinCores
    if (-not $coresPassed) { $allPassed = $false }

    $results += [PSCustomObject]@{
        Check    = "CPU Cores"
        Detected = "$cpuCores cores"
        Required = "$MinCores cores"
        Status   = if ($coresPassed) { "PASS" } else { "FAIL" }
    }
    Write-Log "CPU: $cpuCores logical cores detected (minimum: $MinCores) - $(if ($coresPassed) {'PASS'} else {'FAIL'})" `
        -Level $(if ($coresPassed) {"SUCCESS"} else {"ERROR"})
}
catch {
    $allPassed = $false
    $results += [PSCustomObject]@{
        Check    = "CPU Cores"
        Detected = "Error"
        Required = "$MinCores cores"
        Status   = "FAIL"
    }
    Write-Log "Failed to detect CPU cores: $_" -Level ERROR
}

# --- Disk Space Check ---
try {
    $systemDrive = $env:SystemDrive
    if (-not $systemDrive) { $systemDrive = "C:" }
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'"
    $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    $diskPassed = Test-ResourceThreshold -ActualBytes $disk.FreeSpace -MinimumGB $MinDiskGB
    if (-not $diskPassed) { $allPassed = $false }

    $results += [PSCustomObject]@{
        Check    = "Free Disk ($systemDrive)"
        Detected = "$freeSpaceGB GB"
        Required = "$MinDiskGB GB"
        Status   = if ($diskPassed) { "PASS" } else { "FAIL" }
    }
    Write-Log "Disk ($systemDrive): $freeSpaceGB GB free (minimum: $MinDiskGB GB) - $(if ($diskPassed) {'PASS'} else {'FAIL'})" `
        -Level $(if ($diskPassed) {"SUCCESS"} else {"ERROR"})
}
catch {
    $allPassed = $false
    $results += [PSCustomObject]@{
        Check    = "Free Disk"
        Detected = "Error"
        Required = "$MinDiskGB GB"
        Status   = "FAIL"
    }
    Write-Log "Failed to detect disk space: $_" -Level ERROR
}

# --- Virtualization Check ---
try {
    $vtEnabled = $false
    $vtStatus = "Unknown"

    $hypervisorPresent = (Get-CimInstance -ClassName Win32_ComputerSystem).HypervisorPresent
    if ($hypervisorPresent) {
        $vtEnabled = $true
        $vtStatus = "Enabled (Hypervisor present)"
    }
    else {
        $processor = Get-CimInstance -ClassName Win32_Processor
        if ($processor.VirtualizationFirmwareEnabled) {
            $vtEnabled = $true
            $vtStatus = "Enabled (Firmware)"
        }
        else {
            $vtStatus = "Disabled or not detected"
        }
    }

    if (-not $vtEnabled) { $allPassed = $false }

    $results += [PSCustomObject]@{
        Check    = "Virtualization (VT-x/AMD-V)"
        Detected = $vtStatus
        Required = "Enabled"
        Status   = if ($vtEnabled) { "PASS" } else { "FAIL" }
    }
    Write-Log "Virtualization: $vtStatus - $(if ($vtEnabled) {'PASS'} else {'FAIL'})" `
        -Level $(if ($vtEnabled) {"SUCCESS"} else {"ERROR"})
}
catch {
    $allPassed = $false
    $results += [PSCustomObject]@{
        Check    = "Virtualization (VT-x/AMD-V)"
        Detected = "Error detecting"
        Required = "Enabled"
        Status   = "FAIL"
    }
    Write-Log "Failed to detect virtualization status: $_" -Level ERROR
}

# --- Windows Version Check (informational) ---
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $osVersion = $os.Caption
    $osBuild = $os.BuildNumber
    Write-Log "OS: $osVersion (Build $osBuild)" -Level INFO

    $results += [PSCustomObject]@{
        Check    = "Windows Version"
        Detected = "$osVersion (Build $osBuild)"
        Required = "Windows 10/11"
        Status   = "INFO"
    }
}
catch {
    Write-Log "Could not detect Windows version: $_" -Level WARN
}

# --- Report ---
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor White
Write-Host "  PREREQUISITE CHECK REPORT" -ForegroundColor White
Write-Host ("=" * 70) -ForegroundColor White
$results | Format-Table -AutoSize -Property Check, Detected, Required, Status
Write-Host ("=" * 70) -ForegroundColor White

if ($allPassed) {
    Write-Log "All prerequisite checks PASSED. System is ready for Whonix deployment." -Level SUCCESS
    Write-Host ""
    Write-Host "  [OK] System meets all requirements." -ForegroundColor Green
    Write-Host ""
    exit 0
}
else {
    Write-Log "One or more prerequisite checks FAILED. Cannot proceed with setup." -Level ERROR
    Write-Host ""
    Write-Host "  [BLOCKED] System does not meet minimum requirements." -ForegroundColor Red
    Write-Host "  Resolve the above failures before running setup.ps1." -ForegroundColor Red
    Write-Host ""

    if (-not $vtEnabled) {
        Write-Host "  TIP: Enable VT-x/AMD-V in your BIOS/UEFI settings." -ForegroundColor Yellow
    }

    exit 1
}
