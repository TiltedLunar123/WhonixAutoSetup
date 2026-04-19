#Requires -Version 5.1
<#
.SYNOPSIS
    Starts Whonix Gateway and Workstation VMs in the correct order.
.DESCRIPTION
    Launches the Gateway VM first, waits for Tor to bootstrap by polling
    the Gateway's status, then starts the Workstation VM.
.PARAMETER GatewayVMName
    Name of the Gateway VM in VirtualBox.
.PARAMETER WorkstationVMName
    Name of the Workstation VM in VirtualBox.
.PARAMETER TorTimeoutSeconds
    Maximum seconds to wait for Tor bootstrap before aborting.
.PARAMETER HeadlessGateway
    Start the Gateway in headless mode (no GUI window).
.EXAMPLE
    .\start-whonix.ps1
    .\start-whonix.ps1 -HeadlessGateway -TorTimeoutSeconds 180
#>

[CmdletBinding()]
param(
    [string]$GatewayVMName = "",
    [string]$WorkstationVMName = "",
    [int]$TorTimeoutSeconds = 120,
    [switch]$HeadlessGateway,
    [string]$GuestPassword = "changeme"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path (Join-Path $PSScriptRoot "lib") "logging.ps1")

# ============================================================
# Helper: Find VBoxManage.exe
# ============================================================
function Find-VBoxManage {
    $searchPaths = @(
        (Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Oracle\VirtualBox\VBoxManage.exe")
    )

    $envPath = $env:VBOX_MSI_INSTALL_PATH
    if ($envPath) {
        $searchPaths = @(Join-Path $envPath "VBoxManage.exe") + $searchPaths
    }

    $envPath2 = $env:VBOX_INSTALL_PATH
    if ($envPath2) {
        $searchPaths = @(Join-Path $envPath2 "VBoxManage.exe") + $searchPaths
    }

    foreach ($p in $searchPaths) {
        if (Test-Path $p) { return $p }
    }

    $inPath = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    return $null
}

# ============================================================
# Helper: Get VM state
# ============================================================
function Get-VMState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [string]$VMName
    )

    $info = & $VBoxManage showvminfo $VMName --machinereadable 2>&1 | Out-String
    if ($info -match 'VMState="([^"]+)"') {
        return $Matches[1]
    }
    return "unknown"
}

# ============================================================
# Helper: Start a VM
# ============================================================
function Start-VM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [string]$VMName,
        [string]$Type = "gui"
    )

    $state = Get-VMState -VBoxManage $VBoxManage -VMName $VMName
    if ($state -eq "running") {
        Write-Log "$VMName is already running." -Level WARN
        return
    }

    if ($state -eq "saved" -or $state -eq "paused") {
        Write-Log "Resuming $VMName from $state state..."
        & $VBoxManage controlvm $VMName resume 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to resume $VMName from $state state (exit code $LASTEXITCODE)"
        }
        Write-Log "$VMName resumed." -Level SUCCESS
        return
    }

    Write-Log "Starting $VMName ($Type mode)..."
    & $VBoxManage startvm $VMName --type $Type 2>&1 | ForEach-Object { Write-Log "  $_" -Level DEBUG }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start $VMName"
    }
    Write-Log "$VMName started." -Level SUCCESS
}

# ============================================================
# Health check: Wait for Gateway Tor bootstrap
# ============================================================
function Wait-ForTorBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [int]$TimeoutSeconds = 120
    )

    Write-Banner "Waiting for Tor Bootstrap"
    Write-Log "Polling Gateway for Tor connectivity (timeout: ${TimeoutSeconds}s)..."

    $gatewayIP = "10.152.152.10"
    $pollInterval = 5
    $elapsed = 0

    # Wait for the VM to fully boot before checking Tor
    Write-Log "Waiting 15 seconds for Gateway OS to initialize..."
    Start-Sleep -Seconds 15
    $elapsed = 15

    while ($elapsed -lt $TimeoutSeconds) {
        # Method 1: Try to run a command inside the Gateway via VBoxManage guestcontrol
        # This checks if Tor's control port or SOCKS port is responding
        try {
            $result = & $VBoxManage guestcontrol $GatewayVMName run `
                --exe "/bin/bash" `
                --username user `
                --password $GuestPassword `
                -- -c "systemctl is-active tor@default.service" 2>&1 | Out-String

            if ($result -match "active") {
                Write-Log "Tor service is active on Gateway." -Level SUCCESS

                # Double-check: verify Tor has actually bootstrapped
                $bootstrap = & $VBoxManage guestcontrol $GatewayVMName run `
                    --exe "/bin/bash" `
                    --username user `
                    --password $GuestPassword `
                    -- -c "timeout 5 tor-ctrl -c 'GETINFO status/bootstrap-phase' 2>/dev/null || echo 'check_unavailable'" 2>&1 | Out-String

                if ($bootstrap -match "Bootstrapped 100%" -or $bootstrap -match "PROGRESS=100") {
                    Write-Log "Tor bootstrap complete (100%)." -Level SUCCESS
                    return $true
                }
                elseif ($bootstrap -match "check_unavailable") {
                    # tor-ctrl may not be available; Tor service being active is good enough
                    Write-Log "Tor service active (detailed bootstrap check unavailable)." -Level SUCCESS

                    # Fallback: check if SOCKS port is listening
                    $socksCheck = & $VBoxManage guestcontrol $GatewayVMName run `
                        --exe "/bin/bash" `
                        --username user `
                        --password $GuestPassword `
                        -- -c "ss -tlnp | grep ':9050' || echo 'not_listening'" 2>&1 | Out-String

                    if ($socksCheck -notmatch "not_listening" -and $socksCheck -match "9050") {
                        Write-Log "Tor SOCKS port 9050 is listening. Gateway is ready." -Level SUCCESS
                        return $true
                    }
                }
                else {
                    $progressMatch = [regex]::Match($bootstrap, 'PROGRESS=(\d+)')
                    if ($progressMatch.Success) {
                        Write-Log "  Tor bootstrap progress: $($progressMatch.Groups[1].Value)%"
                    }
                }
            }
        }
        catch {
            # Guest additions may not support guestcontrol; fall back to network check
            Write-Log "  Guest control not available, using network probe..." -Level DEBUG
        }

        # Method 2: Fallback - simple TCP check to Gateway's SOCKS proxy port
        $tcpClient = $null
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connectTask = $tcpClient.ConnectAsync($gatewayIP, 9050)
            $connected = $connectTask.Wait(3000)

            if ($connected) {
                Write-Log "Gateway SOCKS port (9050) is reachable. Tor is ready." -Level SUCCESS
                return $true
            }
        }
        catch {
            # Connection refused or timeout -- Tor not ready yet
        }
        finally {
            if ($tcpClient) {
                $tcpClient.Close()
                $tcpClient.Dispose()
            }
        }

        $remaining = $TimeoutSeconds - $elapsed
        Write-Log "  Tor not ready yet. Retrying in ${pollInterval}s (${remaining}s remaining)..."
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval
    }

    Write-Log "Tor bootstrap timed out after ${TimeoutSeconds} seconds." -Level ERROR
    return $false
}

# ============================================================
# Main Execution
# ============================================================
try {
    Write-Banner "WhonixAutoSetup - Launch"

    $vboxManage = Find-VBoxManage
    if (-not $vboxManage) {
        throw "VBoxManage.exe not found. Run setup.ps1 first."
    }
    Write-Log "Using VBoxManage: $vboxManage"

    # Auto-detect VM names if not specified
    $vmList = & $vboxManage list vms 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list VMs (exit code $LASTEXITCODE): $vmList"
    }
    if ([string]::IsNullOrEmpty($GatewayVMName)) {
        $gwMatch = [regex]::Match($vmList, '"(Whonix-Gateway[^"]*)"')
        if ($gwMatch.Success) { $GatewayVMName = $gwMatch.Groups[1].Value }
        else { throw "No Whonix Gateway VM found. Run setup.ps1 first." }
    }
    if ([string]::IsNullOrEmpty($WorkstationVMName)) {
        $wsMatch = [regex]::Match($vmList, '"(Whonix-Workstation[^"]*)"')
        if ($wsMatch.Success) { $WorkstationVMName = $wsMatch.Groups[1].Value }
        else { throw "No Whonix Workstation VM found. Run setup.ps1 first." }
    }
    Write-Log "Detected Gateway VM:     $GatewayVMName"
    Write-Log "Detected Workstation VM: $WorkstationVMName"

    # Step 1: Start Gateway
    Write-Banner "Starting Whonix Gateway"
    $gwType = if ($HeadlessGateway) { "headless" } else { "gui" }
    Start-VM -VBoxManage $vboxManage -VMName $GatewayVMName -Type $gwType

    # Step 2: Wait for Tor
    $torReady = Wait-ForTorBootstrap -VBoxManage $vboxManage -TimeoutSeconds $TorTimeoutSeconds

    if (-not $torReady) {
        Write-Log "WARNING: Tor bootstrap could not be confirmed." -Level WARN
        Write-Log "The Gateway may still be initializing. Proceeding with Workstation launch..." -Level WARN
        Write-Log "If Workstation has no connectivity, wait a few minutes and check Gateway status." -Level WARN
    }

    # Step 3: Start Workstation
    Write-Banner "Starting Whonix Workstation"
    Start-VM -VBoxManage $vboxManage -VMName $WorkstationVMName -Type "gui"

    Write-Banner "Whonix is Running"
    Write-Log "Gateway:     $GatewayVMName" -Level SUCCESS
    Write-Log "Workstation: $WorkstationVMName" -Level SUCCESS
    Write-Host ""
    Write-Log "Both VMs are now running. The Workstation routes all traffic through the Gateway's Tor connection."
    Write-Log "Log file: $(Get-LogFilePath)"
}
catch {
    Write-Log "LAUNCH FAILED: $_" -Level ERROR
    Write-Log "Check the log file for details: $(Get-LogFilePath)" -Level ERROR
    exit 1
}
