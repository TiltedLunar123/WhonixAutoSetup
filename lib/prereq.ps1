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
