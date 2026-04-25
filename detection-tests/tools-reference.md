# Detection Tools Reference

Versions, source URLs, build instructions, and verification hashes for all tools used in this project.

---

## Pafish

**Purpose:** Parasite Fish — tests for common VM and sandbox detection techniques including CPUID, registry, disk, network, timing, and WMI checks.

**Source:** https://github.com/a0rtega/pafish

**Build (Linux cross-compile for Windows):**
```bash
sudo apt install mingw-w64
git clone https://github.com/a0rtega/pafish
cd pafish
make -f Makefile.win64
# Output: pafish.exe
```

**Run inside VM:**
```
pafish.exe
```
No arguments needed. Output color-codes: green = not detected, red = detected.

---

## Al-Khaser

**Purpose:** Comprehensive anti-analysis technique detector — 100+ checks covering debugger, VM, sandbox, disassembly, and timing detection methods used by real malware.

**Source:** https://github.com/LordNoteworthy/al-khaser

**Build:**
- Requires Visual Studio 2019+ or mingw-w64
- Open `al-khaser.sln` in Visual Studio, build Release x64
- Or cross-compile with mingw-w64 (check project for specific flags)

**Run inside VM:**
```
al-khaser.exe
```
Produces a categorized list of detected/not-detected checks with pass/fail counts.

---

## VMAware

**Purpose:** Header-only C++ library that aggregates 100+ VM detection techniques into a confidence score. Includes a standalone test binary.

**Source:** https://github.com/kernelwernel/VMAware

**Build:**
```bash
# Linux build of the test program (run on Linux host for comparison)
g++ -std=c++17 -o vmaware_test vmaware_test.cpp

# Windows build (cross-compile)
x86_64-w64-mingw32-g++ -std=c++17 -o vmaware_test.exe vmaware_test.cpp
```

**Run inside VM:**
```
vmaware_test.exe
```
Outputs a VM brand guess and confidence percentage (0-100%).

---

## CPU-Z (Portable)

**Purpose:** Displays CPUID, SMBIOS/DMI, and hardware information. Used to visually verify SMBIOS spoofing is working correctly.

**Source:** https://www.cpuid.com/softwares/cpu-z.html (portable .zip version)

**Run inside VM:** Launch `cpuz_x64.exe`, check:
- **CPU tab:** Processor name (should match i7-10700)
- **Mainboard tab:** Manufacturer (should be Dell Inc.), Model (should be OptiPlex 7090)
- **Memory tab:** Manufacturer (Samsung), Part number (M378A1K43EB2-CWE)

---

## HWiNFO64 (Portable)

**Purpose:** Comprehensive hardware enumeration tool. Shows full SMBIOS structure, PCI device tree, and driver information. Most thorough tool for verifying SMBIOS spoofing.

**Source:** https://www.hwinfo.com/download/ (portable version)

**Run inside VM:** Launch `HWiNFO64.exe` in summary mode, check:
- **System Summary:** Manufacturer, Model, Board
- **DMI / SMBIOS section:** All type entries
- **PCI devices:** Will reveal Q35 chipset (known detection limit)

---

## WMI Explorer (Portable)

**Purpose:** Browse all WMI classes interactively. Use to query Win32_ComputerSystem, Win32_BIOS, Win32_DiskDrive, Win32_NetworkAdapter, Win32_VideoController.

**Source:** https://github.com/vinaypamnani/wmie2 or search "WMI Explorer" from Codeplex

**Equivalent PowerShell queries (no extra tool needed):**
```powershell
Get-WmiObject Win32_ComputerSystem | Format-List *
Get-WmiObject Win32_BIOS | Format-List *
Get-WmiObject Win32_DiskDrive | Format-List *
Get-WmiObject Win32_NetworkAdapter | Where-Object PhysicalAdapter | Format-List *
Get-WmiObject Win32_VideoController | Format-List *
Get-WmiObject Win32_BaseBoard | Format-List *
Get-WmiObject Win32_SystemEnclosure | Format-List *
Get-WmiObject Win32_PhysicalMemory | Format-List *
Get-WmiObject Win32_Processor | Format-List *
```

---

## Custom Detector Script

`detection-tests/custom-detector.py` — written as part of Phase 4 of the test methodology. Attempts adversarial consistency checks that commercial tools may not perform.

Checks planned:
1. SMBIOS says "OptiPlex 7090" — verify PCI vendor ID for NIC is actually Intel (0x8086)
2. CPUID leaf 4 (cache topology) consistency with a real i7-10700
3. RDTSC timing measurement with statistical analysis (multiple samples)
4. Battery ACPI method consistency check (_BIF capacity vs _BST remaining)
5. EDID data from connected display matches Dell U2722D signature

---

## Integrity Verification

Record tool binary SHA256 hashes here after download to ensure reproducibility:

| Tool | Version | SHA256 | Date Acquired |
|---|---|---|---|
| pafish.exe | | | |
| al-khaser.exe | | | |
| vmaware_test.exe | | | |
| cpuz_x64.exe | | | |
| HWiNFO64.exe | | | |
