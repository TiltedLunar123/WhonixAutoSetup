#Requires -Version 5.1
<#
.SYNOPSIS
    Shared VirtualBox helpers for WhonixAutoSetup.
.DESCRIPTION
    Locates VBoxManage.exe via env vars, default install paths, and PATH, and
    resolves Whonix VM names out of `VBoxManage list vms` output. Dot-source this
    module from any script that needs the binary or the VM names.
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

function Resolve-WhonixVmName {
    <#
    .SYNOPSIS
        Picks a VM name out of `VBoxManage list vms` output by prefix.
    .DESCRIPTION
        configure-vms.ps1 and start-whonix.ps1 both need to find the Gateway and
        Workstation VMs by their leading name (e.g. "Whonix-Gateway"). The raw
        listing prints one VM per line as:  "Name" {uuid}. This parser pulls the
        quoted names, keeps the ones that start with the prefix, and returns one
        deterministically so a clone or backup can't shadow the real VM depending
        on listing order.

        Selection order: an exact prefix match wins; otherwise the shortest
        candidate (the canonical name, before any " Clone"/"-Backup" suffix);
        alphabetical breaks a length tie. Returns $null when nothing matches so
        the caller can raise its own message.
    .PARAMETER VmListOutput
        Raw text from `VBoxManage list vms`.
    .PARAMETER NamePrefix
        The leading VM name to match, e.g. "Whonix-Gateway".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$VmListOutput,
        [Parameter(Mandatory)] [string]$NamePrefix
    )

    $names = [regex]::Matches($VmListOutput, '"([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value }

    $candidates = @($names | Where-Object { $_.StartsWith($NamePrefix, [System.StringComparison]::Ordinal) })
    if ($candidates.Count -eq 0) { return $null }

    $exact = @($candidates | Where-Object { $_ -ceq $NamePrefix })
    if ($exact.Count -gt 0) { return ($exact | Sort-Object | Select-Object -First 1) }

    # Select-Object -First 1 (not [0]) so a single match returns the whole string
    # rather than indexing into it and handing back its first character.
    return ($candidates |
        Sort-Object @{ Expression = { $_.Length } }, @{ Expression = { $_ } } |
        Select-Object -First 1)
}
