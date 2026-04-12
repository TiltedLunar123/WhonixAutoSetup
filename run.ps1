#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-Location $PSScriptRoot
& .\prereq-check.ps1; if ($LASTEXITCODE -eq 0) { & .\setup.ps1 }; if ($LASTEXITCODE -eq 0) { & .\configure-vms.ps1 }; if ($LASTEXITCODE -eq 0) { & .\start-whonix.ps1 }
