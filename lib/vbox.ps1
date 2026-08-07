#Requires -Version 5.1
<#
.SYNOPSIS
    Shared VirtualBox helpers for WhonixAutoSetup.
.DESCRIPTION
    Locates VBoxManage.exe via env vars, default install paths, and PATH,
    resolves Whonix VM names out of `VBoxManage list vms` output, and maps a
    reported VMState onto the VBoxManage command that actually moves the VM.
    Dot-source this module from any script that needs the binary, the VM names,
    or the state mapping.
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

function Resolve-VmStartAction {
    <#
    .SYNOPSIS
        Maps a VMState onto the VBoxManage command that will start that VM.
    .DESCRIPTION
        VBoxManage subcommands each accept a narrow set of machine states, and
        picking the wrong one fails instead of doing nothing. `controlvm resume`
        restarts a *paused* VM, so aiming it at a saved VM is an error; the
        command that brings a saved VM back is `startvm`, which the manual
        describes as starting a VM that is powered off or in a saved state.

        Returned action, for the caller to act on:
          none        already running, nothing to do
          resume      paused, so `controlvm <vm> resume`
          restore     has a saved state, so `startvm` (restores it)
          start       cold, so `startvm` (fresh boot)
          unsupported mid-transition or unrecognised; the caller should report
                      the state by name rather than fire a command at it

        Keeping this as string in, string out means the whole state table is
        testable without VirtualBox installed.
    .PARAMETER VmState
        The VMState value from `VBoxManage showvminfo --machinereadable`.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$VmState
    )

    switch ($VmState.Trim().ToLowerInvariant()) {
        'running'       { return 'none' }
        'paused'        { return 'resume' }
        'saved'         { return 'restore' }
        # VirtualBox 7 reports a VM whose process died while a saved state was
        # on disk as aborted-saved. The saved state survives, so restore it.
        'aborted-saved' { return 'restore' }
        'poweroff'      { return 'start' }
        # aborted means the VM process died with no saved state, so a cold boot
        # is the only way forward.
        'aborted'       { return 'start' }
        default         { return 'unsupported' }
    }
}

function Resolve-VmPowerOffAction {
    <#
    .SYNOPSIS
        Maps a VMState onto the VBoxManage command that will get that VM to
        powered off, which is the state `modifyvm` needs.
    .DESCRIPTION
        `controlvm poweroff` needs a VM that is actually executing. On a saved
        VM it errors out, so configure-vms.ps1 cannot simply poweroff anything
        that is not already off. A saved VM gets there by discarding the saved
        state instead.

        Returned action, for the caller to act on:
          none         already off as far as modifyvm cares
          poweroff     executing, so `controlvm <vm> poweroff`
          discardstate not executing but holding a saved state, so
                       `discardstate <vm>`
          unsupported  mid-transition or unrecognised; the caller should report
                       the state by name rather than fire a command at it
    .PARAMETER VmState
        The VMState value from `VBoxManage showvminfo --machinereadable`.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$VmState
    )

    switch ($VmState.Trim().ToLowerInvariant()) {
        'poweroff'      { return 'none' }
        # A dead VM process with no saved state is already off on disk.
        'aborted'       { return 'none' }
        'running'       { return 'poweroff' }
        'paused'        { return 'poweroff' }
        # Guru meditation. The guest is wedged but the process is live, so
        # poweroff is the documented way out.
        'stuck'         { return 'poweroff' }
        'saved'         { return 'discardstate' }
        'aborted-saved' { return 'discardstate' }
        default         { return 'unsupported' }
    }
}
