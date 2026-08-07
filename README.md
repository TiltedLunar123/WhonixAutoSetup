# WhonixAutoSetup

[![CI](https://github.com/TiltedLunar123/WhonixAutoSetup/actions/workflows/ci.yml/badge.svg)](https://github.com/TiltedLunar123/WhonixAutoSetup/actions/workflows/ci.yml)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6.svg)](https://www.microsoft.com/windows)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![VirtualBox](https://img.shields.io/badge/VirtualBox-Latest-orange.svg)](https://www.virtualbox.org/)

Fully automated deployment of [Whonix](https://www.whonix.org/) Gateway and Workstation virtual machines on Windows 10/11 using VirtualBox.

---

## What It Does

1. **Validates** your system meets hardware requirements (RAM, CPU, disk, virtualization)
2. **Downloads and installs** VirtualBox + Extension Pack silently
3. **Downloads** the Whonix OVA (bundles both Gateway + Workstation) with SHA-512 verification
4. **Imports** both VMs into VirtualBox
5. **Configures** resource allocation dynamically based on your hardware
6. **Hardens** VMs with security best practices (clipboard isolation, no USB, no shared folders)
7. **Launches** Gateway first, waits for Tor bootstrap, then starts Workstation

## Prerequisites

| Requirement | Minimum |
|---|---|
| Windows | 10 or 11 |
| PowerShell | 5.1+ (built-in) |
| RAM | 8 GB |
| CPU Cores | 4 logical cores |
| Free Disk | 50 GB |
| Virtualization | VT-x or AMD-V enabled in BIOS |

## Quick Start

Open PowerShell **as Administrator** and run:

```powershell
# 1. Check system prerequisites
.\prereq-check.ps1

# 2. Install VirtualBox and download/import Whonix VMs
.\setup.ps1

# 3. Configure VMs with optimal resources and security hardening
.\configure-vms.ps1

# 4. Launch Whonix (Gateway first, then Workstation)
.\start-whonix.ps1
```

Or run all four steps in sequence with a single entry point (it stops if any
step fails):

```powershell
.\run.ps1
```

## Project Structure

```
WhonixAutoSetup/
├── run.ps1                # One-shot: runs all four steps in order
├── prereq-check.ps1       # System requirements validation
├── setup.ps1              # VirtualBox + Whonix OVA installer
├── configure-vms.ps1      # VM resource allocation and hardening
├── start-whonix.ps1       # Ordered VM launch with Tor health check
├── lib/
│   ├── allocation.ps1     # VM RAM/CPU sizing math
│   ├── logging.ps1        # Shared logging utilities
│   ├── prereq.ps1         # Resource-threshold math helper
│   └── vbox.ps1           # VBoxManage.exe locator + Whonix VM-name resolver
├── tests/                 # Pester 5 unit tests for the lib helpers
├── .github/workflows/     # CI: PSScriptAnalyzer + Pester
├── logs/                  # Runtime log files (gitignored)
├── downloads/             # Downloaded OVAs and installers (gitignored)
├── README.md
├── LICENSE
└── .gitignore
```

## Script Details

### prereq-check.ps1

Detects total RAM, CPU cores, free disk space, and hardware virtualization status. Outputs a formatted pass/fail table and blocks setup if minimums are not met.

Custom thresholds:
```powershell
.\prereq-check.ps1 -MinRamGB 16 -MinCores 6 -MinDiskGB 80
```

### setup.ps1

Downloads and silently installs the latest VirtualBox if not already present. Fetches the Whonix OVA (which bundles both Gateway and Workstation VMs) from official mirrors over HTTPS and verifies the SHA-512 checksum before importing.

Options:
```powershell
.\setup.ps1 -WhonixVersion "18.1.4.2"           # Specify Whonix version
.\setup.ps1 -WhonixEdition "CLI"                 # CLI instead of LXQt GUI
.\setup.ps1 -SkipVBoxInstall                     # Skip VirtualBox installation
.\setup.ps1 -DownloadDir "D:\VMs"                # Custom download directory
.\setup.ps1 -VirtualBoxVersion "7.1.4"           # Pin a VirtualBox release
.\setup.ps1 -VirtualBoxVersion "7.1.4" `
            -VirtualBoxHash "<sha256>"           # Reproducible + verified install
```

> Without `-VirtualBoxVersion` the script fetches whatever `LATEST.TXT`
> currently advertises, so two runs on different days may install
> different VirtualBox builds. Pair `-VirtualBoxVersion` with
> `-VirtualBoxHash` (SHA-256) for a reproducible, integrity-checked
> install; mismatch aborts setup. Without `-VirtualBoxHash` the
> installer is executed unverified.

### configure-vms.ps1

Dynamically allocates resources based on your hardware:

| VM | CPU | RAM |
|---|---|---|
| Gateway | 1 core (fixed) | 1 GB (fixed) |
| Workstation | 2-4 cores | 25-40% of available RAM |

Security hardening applied to both VMs:
- Clipboard sharing disabled
- Drag-and-drop disabled
- Shared folders removed
- USB passthrough disabled (all controllers)
- Audio disabled
- 3D acceleration disabled
- Remote desktop (VRDE) disabled
- Nested hardware virtualization disabled

Network configuration:
- **Gateway**: Adapter 1 = NAT (internet), Adapter 2 = Internal Network "Whonix"
- **Workstation**: Adapter 1 = Internal Network "Whonix" only (no direct internet)

### start-whonix.ps1

Launches Gateway first, polls for Tor bootstrap confirmation via guest control and TCP probes, then starts the Workstation.

Options:
```powershell
.\start-whonix.ps1 -HeadlessGateway              # Run Gateway without a window
.\start-whonix.ps1 -TorTimeoutSeconds 180         # Extend Tor wait time
.\start-whonix.ps1 -GuestPassword "mypassword"    # Custom guest VM password (default: changeme)
```

## Logging

All scripts log to `logs/WhonixAutoSetup_<timestamp>.log` with timestamped entries. Console output is color-coded by severity.

## Troubleshooting

| Issue | Solution |
|---|---|
| "Virtualization FAIL" | Enable VT-x/AMD-V in your BIOS/UEFI settings |
| VBoxManage not found | Restart your shell after VirtualBox installation, or set `VBOX_INSTALL_PATH` |
| Checksum mismatch | Delete the file from `downloads/` and re-run `setup.ps1` |
| Tor bootstrap timeout | Increase `-TorTimeoutSeconds` or check Gateway console for errors |
| VM already exists | The scripts skip import if a VM with that name exists; delete it in VirtualBox to reimport |
| Extension Pack install warning | Usually the license hash, which Oracle changes per release. Pass the hash VBoxManage names to `setup.ps1 -ExtPackLicenseHash`, or install the pack by hand. Whonix runs without it |

### Saved VMs

Closing a Whonix window with "Save the machine state", which is the default
button in the VirtualBox close dialog, leaves the VM in `saved` rather than
powered off. The two scripts treat that state differently, because VirtualBox
wants different commands to get out of it:

- `start-whonix.ps1` restores the VM from its saved state. Your session comes
  back where you left it.
- `configure-vms.ps1` has to discard the saved state before it can change CPU,
  RAM, or network settings, since VirtualBox will not reconfigure a VM that is
  holding one. That throws the suspended session away. The script warns before
  it does this. Boot the VM and shut it down from inside the guest first if you
  want to keep the session.

## Development

CI runs PSScriptAnalyzer and Pester on every push and pull request. You can run
the same checks locally before opening a PR:

```powershell
# Install the tooling (once)
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck

# Lint (CI fails on Error-severity findings)
Invoke-ScriptAnalyzer -Path . -Recurse `
    -ExcludeRule PSAvoidUsingWriteHost, PSUseShouldProcessForStateChangingFunctions

# Run the unit tests
Invoke-Pester -Path tests
```

The tests in `tests/` cover the pure helpers in `lib/` and mock VirtualBox and
the filesystem, so they run anywhere without a VM or VirtualBox installed.

## Disclaimer

This project is provided for **educational and legitimate privacy research purposes only**. Users are solely responsible for ensuring their use of Whonix and Tor complies with all applicable laws and regulations in their jurisdiction. The authors do not condone or encourage any illegal activity.

Whonix is a registered trademark of the Whonix project. VirtualBox is a registered trademark of Oracle Corporation. This project is not affiliated with or endorsed by either organization.

## License

[MIT](LICENSE)
