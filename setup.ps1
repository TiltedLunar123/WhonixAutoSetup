#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and installs VirtualBox, Extension Pack, and Whonix OVA.
.DESCRIPTION
    Silently installs VirtualBox if not present, downloads the Whonix OVA
    (which bundles both Gateway and Workstation VMs), verifies the SHA-512
    checksum, and imports the VMs into VirtualBox.
.PARAMETER WhonixVersion
    Whonix release version to download. Defaults to 18.1.4.2.
.PARAMETER WhonixEdition
    Desktop edition: LXQt (GUI) or CLI. Defaults to LXQt.
.PARAMETER DownloadDir
    Directory for downloaded files. Defaults to ./downloads under project root.
.PARAMETER SkipVBoxInstall
    Skip VirtualBox installation (assumes already installed).
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -WhonixVersion "18.1.4.2" -WhonixEdition "CLI"
    .\setup.ps1 -SkipVBoxInstall
#>

[CmdletBinding()]
param(
    [string]$WhonixVersion = "18.1.4.2",
    [ValidateSet("LXQt", "CLI")]
    [string]$WhonixEdition = "LXQt",
    [string]$DownloadDir = "",
    [switch]$SkipVBoxInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path (Join-Path $PSScriptRoot "lib") "logging.ps1")

if ([string]::IsNullOrEmpty($DownloadDir)) {
    $DownloadDir = Join-Path $PSScriptRoot "downloads"
}
if (-not (Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

# --- Configuration ---
$VBoxBaseUrl   = "https://download.virtualbox.org/virtualbox"
$WhonixBaseUrl = "https://download.whonix.org/ova/$WhonixVersion"
$OvaFileName   = "Whonix-$WhonixEdition-$WhonixVersion.Intel_AMD64.ova"
$Sha512Name    = "$OvaFileName.sha512sums"

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
    $lines = @($checksumContent -split "`n" | Where-Object { $_ -match [regex]::Escape($fileName) })

    if ($lines.Count -eq 0) {
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
        if (Test-Path $p) { return $p }
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

    $latestVersionUrl = "$VBoxBaseUrl/LATEST.TXT"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $latestVersion = (Invoke-WebRequest -Uri $latestVersionUrl -UseBasicParsing).Content.Trim()
    Write-Log "Latest VirtualBox version: $latestVersion"

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

    Write-Log "Installing VirtualBox silently (this may take a few minutes)..."
    $process = Start-Process -FilePath $installerPath -ArgumentList @("--silent", "--ignore-reboot") -Wait -PassThru
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
            & $vboxManage extpack install --replace --accept-license=56be48f923303c8cabbd2e31a14ae6b34f8e5264e630d78e6e1ef4630bd573e0 $extPackPath 2>&1 |
                ForEach-Object { Write-Log "  $_" -Level DEBUG }
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
# Step 2: Download Whonix OVA
# ============================================================
function Get-WhonixImage {
    Write-Banner "Step 2: Download Whonix $WhonixEdition $WhonixVersion"

    $ovaPath = Join-Path $DownloadDir $OvaFileName
    $shaPath = Join-Path $DownloadDir $Sha512Name

    Get-FileFromUrl -Url "$WhonixBaseUrl/$Sha512Name" -Destination $shaPath
    Get-FileFromUrl -Url "$WhonixBaseUrl/$OvaFileName" -Destination $ovaPath

    # Verify checksum
    Write-Banner "Step 3: Verify Checksum"
    $valid = Test-Sha512Checksum -FilePath $ovaPath -ChecksumFile $shaPath
    if (-not $valid) {
        throw "Checksum verification failed. The downloaded file may be corrupted or tampered with. Delete it and retry."
    }

    return $ovaPath
}

# ============================================================
# Step 4: Import OVA (creates both Gateway + Workstation VMs)
# ============================================================
function Import-WhonixVMs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$VBoxManage,
        [Parameter(Mandatory)] [string]$OvaPath
    )

    Write-Banner "Step 4: Import VMs into VirtualBox"

    $existingVMs = & $VBoxManage list vms 2>&1 | Out-String

    $gwPattern = "Whonix-Gateway"
    $wsPattern = "Whonix-Workstation"

    if ($existingVMs -match $gwPattern -and $existingVMs -match $wsPattern) {
        Write-Log "Whonix Gateway and Workstation VMs already exist, skipping import." -Level WARN
        return
    }

    Write-Log "Importing Whonix OVA (this creates both Gateway and Workstation VMs)..."
    Write-Log "This may take several minutes for a ~2GB file..."
    Write-Log "Accepting Whonix EULA for both virtual systems..."
    & $VBoxManage import $OvaPath --vsys 0 --eula accept --vsys 1 --eula accept 2>&1 | ForEach-Object { Write-Log "  $_" -Level DEBUG }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to import Whonix OVA."
    }
    Write-Log "Whonix Gateway and Workstation imported successfully." -Level SUCCESS

    # List the imported VMs
    Write-Log "Registered VMs:"
    $vms = & $VBoxManage list vms 2>&1
    $vms | Where-Object { $_ -match "Whonix" } | ForEach-Object { Write-Log "  $_" -Level INFO }
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

    $ovaPath = Get-WhonixImage

    Import-WhonixVMs -VBoxManage $vboxManage -OvaPath $ovaPath

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
