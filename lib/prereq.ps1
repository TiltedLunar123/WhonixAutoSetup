#Requires -Version 5.1
<#
.SYNOPSIS
    Shared prerequisite-check helpers for WhonixAutoSetup.
#>

function Test-ResourceThreshold {
    <#
    .SYNOPSIS
        Tests whether an observed byte count meets a GB-stated minimum.
    .DESCRIPTION
        Win32_ComputerSystem.TotalPhysicalMemory and Win32_LogicalDisk.FreeSpace
        both report bytes that exclude reserved regions, so a system advertised
        as 8 GB or a 50 GB partition typically reports slightly less. SlackMB
        keeps the threshold honest about that gap.
    .PARAMETER ActualBytes
        Observed byte count (RAM, free disk space, etc.).
    .PARAMETER MinimumGB
        The GB-stated minimum the caller wants to enforce.
    .PARAMETER SlackMB
        How many MB below MinimumGB still counts as "meeting spec".
        Defaults to 256 MB, which absorbs typical BIOS/firmware reservations.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [long]$ActualBytes,
        [Parameter(Mandatory)] [int]$MinimumGB,
        [int]$SlackMB = 256
    )
    return ($ActualBytes / 1MB) -ge ($MinimumGB * 1024 - $SlackMB)
}

function Test-VirtualizationFirmwareEnabled {
    <#
    .SYNOPSIS
        Tests whether firmware virtualization is on across every CPU socket.
    .DESCRIPTION
        Get-CimInstance Win32_Processor returns one object per socket, so on a
        two socket host the caller holds a collection, not a single processor.
        Reading .VirtualizationFirmwareEnabled off that collection member
        enumerates into an array, and PowerShell calls any array of two or more
        elements true no matter what is in it. So @($false, $false), a dual
        socket box with VT-x switched off in firmware, passes a plain
        `if ($processor.VirtualizationFirmwareEnabled)`.

        Taking the values as an explicit array and requiring every one of them
        to be true removes the guesswork. An empty set is false: no data is not
        evidence that virtualization is on.
    .PARAMETER FirmwareEnabledValues
        The VirtualizationFirmwareEnabled value from each Win32_Processor
        instance. Pass the whole collection, one entry per socket.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowNull()]
        [object[]]$FirmwareEnabledValues
    )

    if ($null -eq $FirmwareEnabledValues -or $FirmwareEnabledValues.Count -eq 0) {
        return $false
    }

    foreach ($value in $FirmwareEnabledValues) {
        # A socket that reports null has not answered, which is not a yes.
        if ($null -eq $value) { return $false }
        if (-not [bool]$value) { return $false }
    }
    return $true
}
