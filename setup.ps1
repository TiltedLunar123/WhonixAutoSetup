#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and installs VirtualBox, Extension Pack, and Whonix OVAs.
.DESCRIPTION
    Silently installs VirtualBox if not present, downloads Whonix Gateway and
    Workstation OVA images, verifies SHA-512 checksums, and imports the VMs.
.PARAMETER WhonixVersion
    Whonix release version to download. Defaults to 17.
.PARAMETER DownloadDir
    Directory for downloaded files. Defaults to ./downloads under project root.
.PARAMETER SkipVBoxInstall
    Skip VirtualBox installation (assumes already installed).
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -WhonixVersion 17 -SkipVBoxInstall
#>

[CmdletBinding()]
param(
    [string]$WhonixVersion = "17.2.3.1",
    [string]$DownloadDir = "",
    [switch]$SkipVBoxInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib" "logging.ps1")

if ([string]::IsNullOrEmpty($DownloadDir)) {
    $DownloadDir = Join-Path $PSScriptRoot "downloads"
}
if (-not (Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

# --- Configuration ---
$VBoxBaseUrl      = "https://download.virtualbox.org/virtualbox"
$WhonixBaseUrl    = "https://download.whonix.org/ova/$WhonixVersion"
$GatewayOva       = "Whonix-Gateway-Xfce-$WhonixVersion.ova"
$WorkstationOva   = "Whonix-Workstation-Xfce-$WhonixVersion.ova"
$GatewaySha512    = "$GatewayOva.sha512sums"
$WorkstationSha512 = "$WorkstationOva.sha512sums"

Write-Banner "WhonixAutoSetup - Installation"

# ============================================================
# Helper: Download file with progress
# ============================================================
function Get-FileFromUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [string]$Destination
    )

    $fileName = Split-Path $Destination -Leaf
    if (Test-Path $Destination) {
        Write-Log "File already exists, skipping download: $fileName" -Level WARN
        return
    }

    Write-Log "Downloading: $fileName"
    Write-Log "  URL: $Url" -Level DEBUG

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $Destination)
        $webClient.Dispose()

        $sizeBytes = (Get-Item $Destination).Length
        $sizeMB = [math]::Round($sizeBytes / 1MB, 1)
        Write-Log "Downloaded $fileName ($sizeMB MB)" -Level SUCCESS
    }
    catch {
        if (Test-Path $Destination) { Remove-Item $Destination -Force }
        throw "Download failed for $Url : $_"
    }
}

# ============================================================
# Helper: Verify SHA-512 checksum
# ============================================================
function Test-Sha512Checksum {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$ChecksumFile
    )

    $fileName = Split-Path $FilePath -Leaf
    Write-Log "Verifying SHA-512 checksum for $fileName..."

    if (-not (Test-Path $ChecksumFile)) {
        throw "Checksum file not found: $ChecksumFile"
    }

    $checksumContent = Get-Content $ChecksumFile -Raw
    $lines = $checksumContent -split "`n" | Where-Object { $_ -match $fileName }

    if (-not $lines -or $lines.Count -eq 0) {
        throw "No checksum entry found for $fileName in checksum file."
    }

    $expectedHash = ($lines[0].Trim() -split "\s+")[0]

    $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA512).Hash

    if ($actualHash -ieq $expectedHash) {
        Write-Log "Checksum VERIFIED for $fileName" -Level SUCCESS
        return $true
    }
    else {
        Write-Log "Checksum MISMATCH for $fileName" -Level ERROR
        Write-Log "  Expected: $expectedHash" -Level ERROR
        Write-Log "  Actual:   $actualHash" -Level ERROR
        return $false
    }
}

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
        if (Test-Path $p) {
            return $p
        }
    }

    $inPath = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    return $null
}

# ============================================================
# Step 1: Install VirtualBox
# ============================================================
function Install-VirtualBox {
    Write-Banner "Step 1: VirtualBox Installation"

    $vboxManage = Find-VBoxManage
    if ($vboxManage) {
        $vboxVersion = & $vboxManage --version 2>$null
        Write-Log "VirtualBox already installed: v$vboxVersion" -Level SUCCESS
        Write-Log "  Path: $vboxManage"
        return $vboxManage
    }

    if ($SkipVBoxInstall) {
        throw "VirtualBox not found and -SkipVBoxInstall was specified."
    }

    Write-Log "VirtualBox not found. Downloading latest version..."

    # Get latest version number
    $latestVersionUrl = "$VBoxBaseUrl/LATEST.TXT"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $latestVersion = (Invoke-WebRequest -Uri $latestVersionUrl -UseBasicParsing).Content.Trim()
    Write-Log "Latest VirtualBox version: $latestVersion"

    # Find the Windows installer filename from the download page
    $dirUrl = "$VBoxBaseUrl/$latestVersion/"
    $dirPage = (Invoke-WebRequest -Uri $dirUrl -UseBasicParsing).Content
    $installerMatch = [regex]::Match($dirPage, 'VirtualBox-[^"]+Win\.exe')
    if (-not $installerMatch.Success) {
        throw "Could not find Windows installer at $dirUrl"
    }
    $installerName = $installerMatch.Value
    $installerUrl = "$VBoxBaseUrl/$latestVersion/$installerName"
    $installerPath = Join-Path $DownloadDir $installerName

    Get-FileFromUrl -Url $installerUrl -Destination $installerPath

    # Silent install
    Write-Log "Installing VirtualBox silently (this may take a few minutes)..."
    $installArgs = @(
        "--silent"
        "--ignore-reboot"
    )
    $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "VirtualBox installer exited with code $($process.ExitCode)"
    }
    Write-Log "VirtualBox installed successfully." -Level SUCCESS

    # Install Extension Pack
    $extPackMatch = [regex]::Match($dirPage, 'Oracle_VirtualBox_Extension_Pack-[^"]+\.vbox-extpack')
    if ($extPackMatch.Success) {
        $extPackName = $extPackMatch.Value
        $extPackUrl = "$VBoxBaseUrl/$latestVersion/$extPackName"
        $extPackPath = Join-Path $DownloadDir $extPackName

        Write-Log "Downloading VirtualBox Extension Pack..."
        Get-FileFromUrl -Url $extPackUrl -Destination $extPackPath

        $vboxManage = Find-VBoxManage
        if ($vboxManage) {
            Write-Log "Installing Extension Pack..."
            $extArgs = @("extpack", "install", "--replace", "--accept-license=56be48f923303c8cabbd2e31a14ae6b34f8e5264e630d78e6e1ef4630bd573e0", $extPackPath)
            & $vboxManage $extArgs 2>&1 | ForEach-Object { Write-Log "  $_" -Level DEBUG }
            Write-Log "Extension Pack installed." -Level SUCCESS
        }
    }
    else {
        Write-Log "Extension Pack not found on download page, skipping." -Level WARN
    }

    $vboxManage = Find-VBoxManage
    if (-not $vboxManage) {
        throw "VirtualBox installation completed but VBoxManage.exe not found. You may need to restart your shell."
    }
    return $vboxManage
}

# ============================================================
# Step 2: Download Whonix OVAs
# ============================================================
function Get-WhonixImages {
    Write-Banner "Step 2: Download Whonix Images"

    $downloads = @(
        @{ Name = $GatewayOva;       Url = "$WhonixBaseUrl/$GatewayOva" },
        @{ Name = $GatewaySha512;    Url = "$WhonixBaseUrl/$GatewaySha512" },
        @{ Name = $WorkstationOva;   Url = "$WhonixBaseUrl/$WorkstationOva" },
        @{ Name = $WorkstationSha512; Url = "$WhonixBaseUrl/$WorkstationSha512" }
    )

    foreach ($dl in $downloads) {
        $dest = Join-Path $DownloadDir $dl.Name
        Get-FileFromUrl -Url $dl.Url -Destination $dest
    }

    # Verify checksums
    Write-Banner "Step 3: Verify Checksums"

    $gwOvaPath = Join-Path $DownloadDir $GatewayOva
    $gwShaPath = Join-Path $DownloadDir $GatewaySha512
    $wsOvaPath = Join-Path $DownloadDir $WorkstationOva
    $wsShaPath = Join-Path $DownloadDir $WorkstationSha512

    $gwValid = Test-Sha512Checksum -FilePath $gwOvaPath -ChecksumFile $gwShaPath
    $wsValid = Test-Sha512Checksum -FilePath $wsOvaPath -ChecksumFile $wsShaPath

    if (-not $gwValid -or -not $wsValid) {
        throw "Checksum verification failed. Downloaded files may be corrupted or tampered with. Delete them and retry."
    }

    Write-Log "All checksums verified successfully." -Level SUCCESS
    return @{
        GatewayOva    = $gwOvaPath
        WorkstationOva = $wsOvaPath
    }
}

# ============================================================
# Step 4: Import OVAs
# ============================================================
function Import-WhonixVMs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [string]$GatewayOvaPath,
        [Parameter(Mandatory)] [string]$WorkstationOvaPath
    )

    Write-Banner "Step 4: Import VMs into VirtualBox"

    # Check if VMs already exist
    $existingVMs = & $VBoxManage list vms 2>&1
    $gwExists = $existingVMs | Select-String -SimpleMatch "Whonix-Gateway"
    $wsExists = $existingVMs | Select-String -SimpleMatch "Whonix-Workstation"

    if ($gwExists) {
        Write-Log "Whonix-Gateway VM already exists, skipping import." -Level WARN
    }
    else {
        Write-Log "Importing Whonix Gateway OVA (this may take several minutes)..."
        & $VBoxManage import $GatewayOvaPath --vsys 0 2>&1 | ForEach-Object { Write-Log "  $_" -Level DEBUG }
        if ($LASTEXITCODE -ne 0) { throw "Failed to import Whonix Gateway OVA." }
        Write-Log "Whonix Gateway imported successfully." -Level SUCCESS
    }

    if ($wsExists) {
        Write-Log "Whonix-Workstation VM already exists, skipping import." -Level WARN
    }
    else {
        Write-Log "Importing Whonix Workstation OVA (this may take several minutes)..."
        & $VBoxManage import $WorkstationOvaPath --vsys 0 2>&1 | ForEach-Object { Write-Log "  $_" -Level DEBUG }
        if ($LASTEXITCODE -ne 0) { throw "Failed to import Whonix Workstation OVA." }
        Write-Log "Whonix Workstation imported successfully." -Level SUCCESS
    }
}

# ============================================================
# Main Execution
# ============================================================
try {
    # Run prereq check first
    Write-Log "Running prerequisite check..."
    $prereqScript = Join-Path $PSScriptRoot "prereq-check.ps1"
    & $prereqScript
    if ($LASTEXITCODE -ne 0) {
        throw "Prerequisite check failed. Resolve issues before continuing."
    }

    $vboxManage = Install-VirtualBox
    Write-Log "Using VBoxManage: $vboxManage"

    $images = Get-WhonixImages

    Import-WhonixVMs -VBoxManage $vboxManage `
                     -GatewayOvaPath $images.GatewayOva `
                     -WorkstationOvaPath $images.WorkstationOva

    Write-Banner "Installation Complete"
    Write-Log "VirtualBox and Whonix VMs are installed." -Level SUCCESS
    Write-Log "Next step: Run .\configure-vms.ps1 to apply security hardening."
    Write-Log "Log file: $(Get-LogFilePath)"
}
catch {
    Write-Log "SETUP FAILED: $_" -Level ERROR
    Write-Log "Check the log file for details: $(Get-LogFilePath)" -Level ERROR
    exit 1
}
