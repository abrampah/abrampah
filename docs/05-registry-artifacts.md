# Registry Artifact Removal

## A — Detection Vector

Windows maintains registry entries for installed software, hardware drivers, and system configuration. VM software leaves characteristic keys:

**Pafish registry checks (subset):**
```
HKLM\SOFTWARE\Oracle\VirtualBox Guest Additions
HKLM\SOFTWARE\VMware, Inc.\VMware Tools
HKLM\SYSTEM\CurrentControlSet\Services\VBoxGuest
HKLM\SYSTEM\CurrentControlSet\Services\vmci
HKLM\HARDWARE\ACPI\DSDT\VBOX__
HKLM\HARDWARE\ACPI\DSDT\BOCHS_
```

**Al-Khaser service key enumeration:**
Al-Khaser enumerates all services under `HKLM\SYSTEM\CurrentControlSet\Services` looking for names matching patterns: `VBox`, `VMware`, `VirtIO`, `viostor`, `QEMU`.

**WMI service queries:**
```powershell
Get-WmiObject Win32_Service | Where-Object { $_.Name -match "vbox|vmware|virtio|qemu" }
```

## B — Why It Reveals a VM

Each VM platform installs guest additions / integration drivers that leave registry entries:
- **VirtualBox:** `VBoxGuest` driver, Oracle vendor key
- **VMware:** `vmci` (VMware VMCI Bus Device), `vmhgfs` (shared folders)
- **QEMU/KVM:** VirtIO drivers (`viostor`, `NetKVM`, `Balloon`) installed from virtio-win package
- **ACPI:** Windows caches the DSDT OEM ID (`BOCHS_` or `QEMU`) under `HKLM\HARDWARE\ACPI\DSDT`

Even without guest additions, the VirtIO drivers required for performance (storage, network) leave detectable service keys.

## C — Evasion Implementation

`scripts/registry-patch.ps1` handles this in 6 sections:

**Section 1 — VM vendor software keys:**
Removes `HKLM\SOFTWARE\Oracle`, `HKLM\SOFTWARE\VMware, Inc.`, `HKLM\SOFTWARE\QEMU`, and 32-bit Wow6432Node equivalents.

**Section 2 — VM service registrations:**
Enumerates `HKLM\SYSTEM\CurrentControlSet\Services` and removes any entries matching VirtIO, QEMU, VBox, VMware, or VMX patterns. This is safe because by the time the script runs, drivers are already loaded — the kernel holds them in memory regardless of registry state.

**Section 3 — ACPI string caches:**
Enumerates `HKLM\HARDWARE\ACPI` recursively and removes any subkeys matching `BOCHS|QEMU|VBOX|VIRT`. Combined with the ACPI SSDT override (which changes the OEM ID for new reboots), this ensures the cached values are also cleared.

**Section 4 — Display adapter strings:**
Patches `DriverDesc` and `ProviderName` under the display class GUID `{4D36E968-...}` from "Red Hat VirtIO GPU" to "Intel(R) UHD Graphics 630".

**Section 5 — Network adapter strings:**
Same approach for NIC class GUID `{4D36E972-...}`: VirtIO NIC → Intel I219-V.

**Section 6 — Hyper-V metadata:**
Removes `HKLM\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters` (set by Hyper-V) and the `VirtualizationBasedSecurityStatus` value.

## D — Defensive Implications

Registry-based detection is relatively weak because it requires the malware to actively read the registry — any detection that depends on checking whether specific software is *installed* can be defeated by not installing it (e.g., skipping VMware Tools) or removing the keys post-install.

More robust approaches:
- **Driver binary inspection:** Even with service registry keys removed, the actual driver `.sys` binaries remain in `C:\Windows\System32\drivers\`. Checking for `viostor.sys`, `NetKVM.sys`, etc., is harder to defeat without removing the drivers entirely (which breaks functionality).
- **PnP device enumeration:** VirtIO devices appear in the PnP device tree with specific vendor/device IDs (e.g., Red Hat `1AF4:1041` for NVMe). Renaming the INF strings doesn't change the hardware IDs.
- **Audit log analysis:** A sandbox can check the Windows event log for VM-related installer events, which are harder to retroactively remove.

The driver INF renaming (`scripts/driver-rename.py`) combined with registry patching provides a good surface-level defense, but hardware PCI IDs remain a persistent artifact — see `docs/06-driver-artifacts.md`.
