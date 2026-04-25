# Driver Artifact Evasion

## A — Detection Vector

Windows device drivers expose identity information through multiple channels:

**1. Driver Description (user-visible strings):**
```powershell
Get-WmiObject Win32_NetworkAdapter | Select Name, MACAddress
# "Red Hat VirtIO Ethernet Adapter" is a clear VM indicator

Get-WmiObject Win32_VideoController | Select Name
# "Red Hat VirtIO GPU" or "VMware SVGA 3D"
```

**2. PCI Hardware IDs:**
Every PCI device has a vendor ID and device ID burned into hardware (or emulated by the hypervisor). VirtIO devices use Red Hat's vendor ID:
```
PCI\VEN_1AF4&DEV_1041  — VirtIO NVMe controller
PCI\VEN_1AF4&DEV_1000  — VirtIO NIC (legacy)
PCI\VEN_1AF4&DEV_1041  — VirtIO NVMe
PCI\VEN_1AF4&DEV_1050  — VirtIO GPU
```
Device Manager and WMI `Win32_PnPEntity` expose these.

**3. INF file strings:**
The `.inf` driver installation file contains `DriverDesc`, `Provider`, and service name strings. These are read by Windows during driver installation and cached in the registry.

## B — Why It Reveals a VM

VirtIO drivers use Red Hat's PCI vendor ID (`0x1AF4`) and device IDs assigned from the VirtIO specification. These are hardcoded in the driver binaries and QEMU's device emulation — changing them requires either modifying QEMU source or using a different (slower) emulated device.

The INF file vendor strings ("Red Hat, Inc.") are separate from the PCI IDs — they're cosmetic labels used in Device Manager — but both are checked by detection tools.

## C — Evasion Implementation

**Strategy 1 — INF string patching (before install):**
`scripts/driver-rename.py` patches VirtIO `.inf` files before driver installation:
- "Red Hat VirtIO Ethernet Adapter" → "Intel(R) Ethernet Connection I219-V"
- "Red Hat VirtIO SCSI controller" → "Intel(R) RST SATA Controller"
- "Red Hat VirtIO GPU" → "Intel(R) UHD Graphics 630"
- "Red Hat, Inc." → "Intel Corporation"

This changes what appears in Device Manager and WMI string queries, but does NOT change the PCI hardware IDs.

**Strategy 2 — Use non-VirtIO emulated devices:**
For the NIC, use QEMU's `e1000e` model instead of VirtIO:
```bash
-device e1000e,netdev=net0,mac="${MAC_ADDR}"
```
`e1000e` emulates an Intel I219 NIC with PCI vendor `0x8086` (Intel) and device `0x15D7` — the correct IDs for an Intel I219-V. This eliminates the Red Hat PCI vendor ID for the NIC entirely.

For storage, use `nvme` device model (not VirtIO block):
```bash
-device nvme,drive=drive0,serial="S4EWNX0R123456",model="Samsung SSD 970 EVO Plus 1TB"
```
QEMU's NVMe emulation uses standard NVMe PCI IDs that don't expose a VM vendor.

**Strategy 3 — Post-install registry patch:**
`scripts/registry-patch.ps1` Sections 4 and 5 patch the display and NIC driver description strings in the device class registry keys — a fallback for driver strings that weren't patched pre-install.

**Remaining VirtIO usage:**
Some VirtIO devices (balloon memory driver, RNG, serial) may still be present with Red Hat PCI IDs. For the GPU, `virtio-vga` has no equivalent in the `e1000e`/NVMe category — GPU passthrough or software rendering is the alternative. See `docs/09-gpu.md`.

## D — Defensive Implications

**PCI vendor ID is the most reliable artifact:**
PCI IDs are not stored in the registry and cannot be changed by registry patching. They are part of the PCI Configuration Space, which the guest reads via `In/OutPort` instructions. To spoof them, the hypervisor must intercept PCI config space reads — QEMU does not do this by default for most devices.

**WMI Win32_PnPEntity is resilient:**
Even after INF patching and registry cleanup, `Win32_PnPEntity` returns the hardware IDs from PCI config space:
```
VEN_1AF4&DEV_1050  — Still reveals Red Hat vendor for VirtIO GPU
```

**Defending against driver evasion:**
- Check hardware IDs (`Win32_PnPEntity.HardwareID`) rather than friendly driver names
- Build a whitelist of expected PCI vendor/device ID combinations for the claimed hardware model (Dell OptiPlex 7090 has specific chipset, NIC, and GPU IDs)
- Any VirtIO VEN_1AF4 device in a claimed Dell machine is an immediate red flag
