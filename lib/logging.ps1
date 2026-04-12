#Requires -Version 5.1
<#
.SYNOPSIS
    Shared logging utilities for WhonixAutoSetup.
.DESCRIPTION
    Provides consistent logging to both console and a timestamped log file.
    All scripts dot-source this module for unified log output.
#>

$Script:LogDir = Join-Path (Join-Path $PSScriptRoot "..") "logs"
if (-not (Test-Path $Script:LogDir)) {
    New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
}

$Script:LogFile = Join-Path $Script:LogDir ("WhonixAutoSetup_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "WARN"    { Write-Host $entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        "DEBUG"   { Write-Host $entry -ForegroundColor Gray }
        default   { Write-Host $entry -ForegroundColor Cyan }
    }

    Add-Content -Path $Script:LogFile -Value $entry -Encoding UTF8
}

function Write-Banner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $border = "=" * 60
    Write-Host ""
    Write-Host $border -ForegroundColor Magenta
    Write-Host "  $Title" -ForegroundColor Magenta
    Write-Host $border -ForegroundColor Magenta
    Write-Host ""

    $entry = "`n$border`n  $Title`n$border"
    Add-Content -Path $Script:LogFile -Value $entry -Encoding UTF8
}

function Get-LogFilePath {
    return $Script:LogFile
}
