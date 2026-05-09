#Requires -Version 5.1
<#
.SYNOPSIS
    Shared VirtualBox helpers for WhonixAutoSetup.
.DESCRIPTION
    Locates VBoxManage.exe via env vars, default install paths, and PATH.
    Dot-source this module from any script that needs the binary.
#>

function Find-VBoxManage {
    [CmdletBinding()]
    [OutputType([string])]
    param()

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
