# Known Bugs

## [Severity: High] Unchecked VBoxManage exit code on VM resume
- **File:** start-whonix.ps1:99
- **Issue:** `controlvm $VMName resume` doesn't check `$LASTEXITCODE`; a failed resume (e.g. corrupt saved state) is treated as success.
- **Repro:** Put a VM into saved state, corrupt the save, run the script — it claims the VM started while it is still paused/off.
- **Fix:** Add `if ($LASTEXITCODE -ne 0) { throw "Failed to resume $VMName" }` after the call.

## [Severity: High] TcpClient leak in Tor bootstrap poll
- **File:** start-whonix.ps1:187-201
- **Issue:** `TcpClient` created at line 188 is not disposed when `ConnectAsync` or subsequent code throws; repeated polls leak handles.
- **Repro:** Run the script with the Gateway's SOCKS port blocked so bootstrap never succeeds — `netstat`/handle count climbs until the script exits.
- **Fix:** Wrap in `try { ... } finally { $tcpClient?.Close(); $tcpClient?.Dispose() }`.

## [Severity: Medium] `VBoxManage list vms` exit code ignored
- **File:** setup.ps1:263, 284
- **Issue:** Exit codes on `& $VBoxManage list vms` are never checked; if the command fails, empty output is treated as "no VMs", skipping or duplicating import logic.
- **Repro:** Stop the VirtualBox service or break VBoxManage — script proceeds with wrong assumptions.
- **Fix:** Check `$LASTEXITCODE` after each call or centralize through an `Invoke-VBoxManage` wrapper that throws on failure.

## [Severity: Medium] VirtualBox installer downloaded without signature verification
- **File:** setup.ps1:174-226
- **Issue:** Only the Whonix OVA gets SHA-512 verification; the VirtualBox installer is executed after a version-string match with no hash or GPG check.
- **Repro:** A compromised mirror or DNS hijack serves a malicious VirtualBox installer — script installs it silently.
- **Fix:** Pull the official SHA256SUMS file and verify, or accept a `-VirtualBoxHash` parameter.

## [Severity: Medium] Hardcoded default Whonix password in guest control
- **File:** start-whonix.ps1:140, 150, 165
- **Issue:** Guest-control invocations hardcode `changeme`; anyone with access to script logs sees the credential and the script assumes the user never changed it.
- **Repro:** Run the script after changing the Whonix password — all guestcontrol calls fail with auth error.
- **Fix:** Accept the password as a secure parameter or environment variable; document the default.

## [Severity: Low] VirtualBox pinned to "latest", non-reproducible installs
- **File:** setup.ps1:176-179
- **Issue:** README says installer is silent, but never mentions that "latest" is fetched at runtime; two runs on different days can install different VirtualBox versions.
- **Repro:** Run before and after a VirtualBox release — different binaries installed.
- **Fix:** Add a `-VirtualBoxVersion` parameter (mirroring `-WhonixVersion`) for reproducible installs.

## [Severity: Low] OVA not cleaned up when import fails
- **File:** setup.ps1:277-279
- **Issue:** Import failure leaves the (potentially corrupt) OVA in `downloads/`, confusing retries.
- **Repro:** Run with a full disk or bad permissions; OVA remains and is trusted on the next run.
- **Fix:** Delete the OVA in the catch/failure branch before rethrowing.

## [Severity: Low] Guest Additions availability not verified before `guestcontrol`
- **File:** start-whonix.ps1:137-141, 147-151, 162-166
- **Issue:** Script assumes guest additions are installed; when they're absent/stale every guestcontrol call fails and the TCP fallback may give false negatives.
- **Repro:** Use a Whonix image without guest additions — Tor bootstrap times out while Tor is actually running.
- **Fix:** Probe `guestcontrol ... stat` (or `VBoxService` status) once; if unavailable, log clearly and skip directly to TCP probing.
