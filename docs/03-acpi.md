# ACPI Table Manipulation

## A — Detection Vector

ACPI (Advanced Configuration and Power Interface) tables are provided by firmware and describe hardware topology to the OS. The DSDT (Differentiated System Description Table) contains an OEM ID field that QEMU fills with `BOCHS` or `QEMU`.

**Windows caches ACPI strings in the registry:**
```
HKLM\HARDWARE\ACPI\DSDT\<OEM_ID>\<OEM_TABLE_ID>\<OEM_REVISION>
```

Pafish checks this key for `VBOX__`, `BOCHS`, `BXPC`, and `QEMU` subkeys.

**Battery presence check:**
Many malware families check for battery presence as a laptop/physical machine indicator. Physical machines have batteries; sandboxes almost never do. The check uses ACPI:
```c
// WMI-based battery check
Get-WmiObject Win32_Battery
// Or direct ACPI query via DeviceIoControl(IOCTL_BATTERY_QUERY_STATUS)
```
An empty result (no battery) is treated as a VM indicator.

## B — Why It Reveals a VM

QEMU's DSDT is generated at build time with a fixed OEM ID of `BOCHS` and OEM Table ID of `BXPC` — a reference to Bochs, the CPU emulator that predated QEMU. This is hardcoded in QEMU source (`hw/acpi/bios-tables-aml.c`).

Physical laptops have battery devices defined in their DSDT/SSDT. Desktop machines (including the Dell OptiPlex 7090 we're impersonating) do NOT have batteries, but almost no sandbox includes a fake battery device either — so its absence isn't the tell. The issue is that even sophisticated sandboxes often fail to inject realistic ACPI tables.

## C — Evasion Implementation

**SSDT Override (preferred approach):**

Rather than patching the DSDT (which requires recompiling QEMU or applying ACPI firmware blobs), we inject a Supplemental System Description Table (SSDT) that adds new ACPI objects on top of QEMU's existing DSDT.

Source: `vm/acpi/SSDT-fake-battery.dsl`
Binary: `vm/acpi/SSDT-fake-battery.aml` (compile with `build-acpi.sh`)

The SSDT:
1. Sets Dell OEM ID and Table ID in the header: `"DELL  "` / `"DELL7090"`
2. Defines a fake AC adapter device (`AC0`) that is always present and online
3. Defines a fake battery device (`BAT0`) reporting ~50% charge on a 68Wh Li-Ion pack

**QEMU invocation:**
```bash
-acpitable file=vm/acpi/SSDT-fake-battery.aml
```

**Registry cleanup** (for cached DSDT OEM strings):
`scripts/registry-patch.ps1` Section 3 removes any cached `BOCHS`/`QEMU` subkeys under `HKLM\HARDWARE\ACPI\DSDT`.

**Verification inside the VM:**
After injection, the battery should appear in Device Manager → Batteries → "Dell DELL-7DYG4". Check with:
```powershell
Get-WmiObject Win32_Battery | Select-Object Name, Status, BatteryStatus, EstimatedChargeRemaining
```

## D — Defensive Implications

ACPI manipulation is an effective but underutilized evasion technique. Most sandbox ACPI tables are obviously artificial.

Defenses:
- **ACPI OEM ID checking:** Sandboxes should inject realistic ACPI tables with OEM IDs matching their claimed hardware. This is operationally complex but defeats the registry-based OEM string check.
- **Battery consistency:** A sandbox could inject a fake battery whose charge level changes over time (draining while running), making it more convincing. Static battery state is slightly suspicious.
- **ACPI consistency analysis:** A sophisticated detector could cross-reference the ACPI thermal zone names, CPU socket definitions, and PCI routing tables against known hardware. Mismatches with the claimed SMBIOS model reveal inconsistencies.

The fundamental challenge is that realistic ACPI tables require per-hardware customization — there is no generic "looks like a Dell OptiPlex 7090" ACPI blob. Creating one requires either actual hardware to dump, or extremely detailed public documentation.
