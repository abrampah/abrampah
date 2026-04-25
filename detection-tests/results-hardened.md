# Hardened Detection Results

**VM Configuration:** All anti-detection techniques applied (see `vm/launch.sh`)  
**Guest OS:** Windows 11 Pro 23H2  
**Drivers:** VirtIO patched with `scripts/driver-rename.py`  
**Registry:** Patched with `scripts/registry-patch.ps1`  
**Date:** _(fill in when run)_  
**Tester:** _(fill in)_

---

## Instructions

Run all tools according to `methodology.md` Phase 3 after applying all techniques.  
Compare to `results-baseline.md`.  
Replace each `[RESULT]` with `DETECTED` or `NOT_DETECTED`.

---

## Pafish Results (Hardened)

| Check Category | Specific Check | Baseline | Hardened | Technique Applied |
|---|---|---|---|---|
| CPU | CPUID hypervisor present bit | DETECTED | [RESULT] | `hypervisor=off` |
| CPU | Hypervisor vendor = KVMKVMKVM | DETECTED | [RESULT] | `kvm=off` |
| CPU | Hypervisor vendor = Microsoft Hv | DETECTED | [RESULT] | `kvm hidden` |
| CPU | Number of CPUs | [baseline] | [RESULT] | |
| Timing | RDTSC delta over CPUID barrier | DETECTED | [RESULT] | `+invtsc` |
| Timing | RDTSC delta between GetTickCount | DETECTED | [RESULT] | RTC slew |
| Timing | RDTSCP consecutive timing | DETECTED | [RESULT] | `+invtsc` |
| Registry | HKLM\HARDWARE\ACPI\DSDT BOCHS/QEMU | DETECTED | [RESULT] | ACPI SSDT + registry patch |
| Registry | VM vendor software keys | DETECTED | [RESULT] | `registry-patch.ps1` |
| Disk | Drive model VBOX/QEMU/VIRTUAL | DETECTED | [RESULT] | NVMe Samsung model string |
| Display | Screen resolution | [baseline] | [RESULT] | |
| Network | MAC OUI VM vendor | DETECTED | [RESULT] | `mac-spoof.sh` |
| Process | VM processes running | [baseline] | [RESULT] | No VMware/VBox tools |
| WMI | Win32_BIOS Manufacturer | DETECTED | [RESULT] | SMBIOS type=0 |
| BIOS | Firmware vendor string | DETECTED | [RESULT] | OVMF + SMBIOS type=0 |

**Pafish total detected (hardened):** [X/15]  
**Improvement:** [baseline_count - hardened_count] fewer detections

---

## Al-Khaser Results (Hardened)

| Category | Baseline Detected | Hardened Detected | Delta |
|---|---|---|---|
| Anti-Debugging | | | |
| Anti-VM | | | |
| Anti-Sandbox | | | |
| Timing Attacks | | | |

---

## VMAware Result (Hardened)

**Confidence score:** [X]%  
**Baseline score:** [X]%  
**Improvement:** [X]% reduction

---

## WMI Query Results (Hardened)

```
Win32_ComputerSystem:
  Manufacturer: [expected: Dell Inc.]
  Model: [expected: OptiPlex 7090]

Win32_BIOS:
  Manufacturer: [expected: Dell Inc.]
  SMBIOSBIOSVersion: [expected: 1.18.0]

Win32_VideoController:
  Name: [expected: Intel(R) UHD Graphics 630]

Win32_NetworkAdapter (physical):
  Name: [expected: Intel(R) Ethernet Connection I219-V]
  MACAddress: [expected: 00:14:22:xx:xx:xx]

Win32_DiskDrive:
  Model: [expected: Samsung SSD 970 EVO Plus 1TB]
```

---

## HWiNFO64 SMBIOS Section (Hardened)

| Field | Expected Value | Actual Value |
|---|---|---|
| System Manufacturer | Dell Inc. | [fill in] |
| System Product Name | OptiPlex 7090 | [fill in] |
| BIOS Vendor | Dell Inc. | [fill in] |
| BIOS Version | 1.18.0 | [fill in] |
| Board Manufacturer | Dell Inc. | [fill in] |
| Board Product | 0TT6JF | [fill in] |
| Memory Manufacturer | Samsung | [fill in] |
| Memory Part Number | M378A1K43EB2-CWE | [fill in] |

---

## Remaining Detections (Expected Research Findings)

The following checks are expected to remain detected even with all techniques applied.  
These represent fundamental limits of software-only VM emulation:

| Check | Why It Remains | Possible Mitigation |
|---|---|---|
| RDTSC timing variance | VM exits for CPUID add measurable latency | Hardware-assisted CPUID passthrough (Intel TDX, AMD SEV-SNP) — out of scope |
| CPUID leaf 0x40000001 | KVM may still expose a signature leaf | Test and document; may require kernel patch |
| PCI bus topology | Q35 PCIe bridge not present in real OptiPlex | Custom DSDT/SSDT to modify PCI topology |
| E820 memory map | VM-specific memory hole patterns | Custom ACPI tables for memory map |

---

## Screenshot Files

`screenshots/hardened-final/`

---

## Conclusion

_(Fill in after testing)_

Summarize:
- Total checks defeated (baseline → hardened delta)
- Which technique had the highest individual impact
- Which checks remain and why
- Implications for sandbox design
