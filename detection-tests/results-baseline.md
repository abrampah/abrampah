# Baseline Detection Results

**VM Configuration:** Stock QEMU — no anti-detection flags applied  
**Guest OS:** Windows 11 Pro 23H2  
**Drivers:** Default VirtIO (unpatched)  
**Date:** _(fill in when run)_  
**Tester:** _(fill in)_

---

## Instructions

Run all tools according to `methodology.md` Phase 1 before filling in this document.  
Replace each `[RESULT]` with `DETECTED` or `NOT_DETECTED`.  
Add screenshots to `screenshots/baseline/`.

---

## Pafish Results

| Check Category | Specific Check | Result | Notes |
|---|---|---|---|
| CPU | CPUID hypervisor present bit | [RESULT] | CPUID leaf 1 ECX bit 31 |
| CPU | Hypervisor vendor = KVMKVMKVM | [RESULT] | CPUID leaf 0x40000000 |
| CPU | Hypervisor vendor = Microsoft Hv | [RESULT] | Hyper-V leaf |
| CPU | Number of CPUs (single CPU check) | [RESULT] | |
| Timing | RDTSC delta over CPUID barrier | [RESULT] | Threshold: ~1000 cycles |
| Timing | RDTSC delta between GetTickCount calls | [RESULT] | |
| Timing | RDTSCP consecutive timing | [RESULT] | |
| Registry | HKLM\HARDWARE\ACPI\DSDT contains BOCHS/QEMU | [RESULT] | |
| Registry | VM vendor software keys present | [RESULT] | Oracle, VMware, QEMU |
| Disk | Drive model contains VBOX/QEMU/VIRTUAL | [RESULT] | WMI Win32_DiskDrive |
| Display | Screen resolution < 800x600 | [RESULT] | |
| Network | MAC address OUI = VM vendor prefix | [RESULT] | 52:54:00, 08:00:27 |
| Process | vmtoolsd.exe, VBoxService.exe running | [RESULT] | |
| WMI | Win32_BIOS Manufacturer = BOCHS/QEMU/VBOX | [RESULT] | |
| BIOS | Firmware vendor string = BOCHS/SeaBIOS | [RESULT] | |

**Pafish total detected:** [X/15]

---

## Al-Khaser Results

_(Run al-khaser.exe and record category totals)_

| Category | Checks Run | Detected |
|---|---|---|
| Anti-Debugging | | |
| Anti-Disassembly | | |
| Anti-VM | | |
| Anti-Sandbox | | |
| Anti-Dump | | |
| Timing Attacks | | |

**Al-Khaser total detected:** [X/total]

---

## VMAware Result

**Confidence score (baseline):** [X]%  
**Top contributing factors:**
1. 
2. 
3. 

---

## WMI Query Results (baseline)

```
Win32_ComputerSystem:
  Manufacturer: [fill in — expected: QEMU or empty]
  Model: [fill in — expected: Standard PC (Q35 + ICH9, 2009) or similar]

Win32_BIOS:
  Manufacturer: [fill in — expected: SeaBIOS or BOCHS]
  SMBIOSBIOSVersion: [fill in]

Win32_VideoController:
  Name: [fill in — expected: Red Hat VirtIO GPU or SVGA 3D]

Win32_NetworkAdapter (physical):
  Name: [fill in — expected: Red Hat VirtIO Ethernet Adapter]
  MACAddress: [fill in — expected: 52:54:00:xx:xx:xx]

Win32_DiskDrive:
  Model: [fill in — expected: QEMU HARDDISK or virtio-blk]
```

---

## HWiNFO64 SMBIOS Section (baseline)

| Field | Value |
|---|---|
| System Manufacturer | [fill in] |
| System Product Name | [fill in] |
| System Version | [fill in] |
| BIOS Vendor | [fill in] |
| BIOS Version | [fill in] |
| Board Manufacturer | [fill in] |
| Board Product | [fill in] |

---

## CPU-Z Results (baseline)

| Field | Value |
|---|---|
| Processor Name | [fill in] |
| Platform | [fill in] |
| Manufacturer (SMBIOS) | [fill in] |
| Board Model | [fill in] |

---

## Summary

**Total checks detected across all tools:** [X]  
**Most significant detections:**
1. 
2. 
3. 

**Screenshot files:** `screenshots/baseline/`
