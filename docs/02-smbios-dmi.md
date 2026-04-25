# SMBIOS/DMI Spoofing

## A — Detection Vector

SMBIOS (System Management BIOS) is a standard interface through which firmware exposes hardware identity information to the OS. Windows exposes this via WMI and SMBIOS API:

**WMI queries used by detection tools:**
```powershell
# System manufacturer and model — most commonly checked
Get-WmiObject Win32_ComputerSystem | Select Manufacturer, Model

# BIOS vendor — often reveals BOCHS, SeaBIOS, or QEMU
Get-WmiObject Win32_BIOS | Select Manufacturer, SMBIOSBIOSVersion, Version

# Baseboard (motherboard)
Get-WmiObject Win32_BaseBoard | Select Manufacturer, Product

# Memory — Samsung vs "QEMU RAM" labels
Get-WmiObject Win32_PhysicalMemory | Select Manufacturer, PartNumber

# Processor
Get-WmiObject Win32_Processor | Select Name, Manufacturer
```

Al-Khaser checks `Win32_ComputerSystem.Manufacturer` for strings containing `QEMU`, `VirtualBox`, `VMware`, `Xen`, `Bochs`, `Innotek`.

Pafish checks registry keys under `HKLM\HARDWARE\ACPI\DSDT` for OEM ID strings that QEMU writes into the DSDT: `BOCHS`, `BXPC`, `QEMU`.

## B — Why It Reveals a VM

QEMU builds its SMBIOS tables at VM startup with default values:
- Type 1 (System): Manufacturer = `QEMU`, Product = `Standard PC (Q35 + ICH9, 2009)`
- Type 0 (BIOS): Vendor = `SeaBIOS` (or `EFI Development Kit II / OVMF`)
- ACPI DSDT OEM ID = `BOCHS` or `QEMU`

These strings exist because QEMU makes no effort to hide its identity by default — it is primarily a development and testing tool.

## C — Evasion Implementation

QEMU's `-smbios` flag overrides individual SMBIOS table entries by type number. We impersonate a **Dell OptiPlex 7090** with an **Intel Core i7-10700** — a common enterprise desktop.

**All `-smbios` flags used (in `vm/launch.sh`):**

```bash
# Type 0 — BIOS
-smbios type=0,vendor="Dell Inc.",version="1.18.0",date="11/02/2022",release=1.18

# Type 1 — System (the most-checked type)
-smbios type=1,\
  manufacturer="Dell Inc.",\
  product="OptiPlex 7090",\
  version="Not Specified",\
  serial="ABCD1234",\
  uuid="44454C4C-4700-1052-8050-C3C04F325931",\
  sku="OptiPlex 7090",\
  family="OptiPlex"

# Type 2 — Baseboard
-smbios type=2,manufacturer="Dell Inc.",product="0TT6JF",version="A01",\
  serial="CN7692370D05F5."

# Type 3 — Chassis
-smbios type=3,manufacturer="Dell Inc.",version="Not Specified",serial="ABCD1234"

# Type 4 — Processor
-smbios type=4,sock_pfx="CPU",manufacturer="Intel",\
  version="Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz",\
  max-speed=4800,current-speed=2900

# Type 17 — Memory Device
-smbios type=17,manufacturer="Samsung",serial="87654321",\
  asset="Not Specified",part="M378A1K43EB2-CWE",speed=3200
```

**UUID note:** The UUID `44454C4C-...` encodes "DELL" in the first 4 bytes (hex: 44=D, 45=E, 4C=L, 4C=L). This is a real Dell UUID format. A random UUID would also work but looks less authentic in tools like HWiNFO.

## D — Defensive Implications

SMBIOS spoofing is essentially undetectable by the guest at runtime — the values are supplied by the hypervisor before the guest OS boots, and there is no guest-accessible way to verify them.

Defenses must look for *cross-source inconsistencies*:
- **PCI device tree:** SMBIOS says Dell OptiPlex 7090 (uses an Intel H470 chipset), but the PCI device tree shows a Q35/ICH9 bridge (QEMU's default). Real OptiPlex 7090s do not have Q35.
- **CPU microcode version:** QEMU passes through the host's microcode version via `host-passthrough`; this should be consistent with the claimed CPU model but may not be.
- **Thermal/power management:** ACPI thermal zones and CPU frequency scaling behavior may differ from the claimed hardware.

The most robust sandbox defense against SMBIOS spoofing is to not rely on SMBIOS strings at all, and instead use multiple independent detection vectors simultaneously.
