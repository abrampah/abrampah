# Tools Reference

## Primary Research Targets (Proctoring Software)

### Respondus LockDown Browser

**Acquisition:** Provided by your university — log in to the Respondus student portal via your institution's LMS (Canvas, Blackboard, Moodle). Direct download from respondus.com requires an institutional license.

**Version to test:** Latest available from your institution

**Installation in VM:**
1. Download the installer inside the VM (or copy from host via shared drive)
2. Run `LockDownBrowserSetup.exe` as Administrator
3. After install, the browser appears as a shortcut; launching it triggers all checks

**Self-check / demo mode:**
Respondus offers a "practice quiz" mode accessible via Canvas without a real exam scheduled. Use this to test VM detection without requiring an active exam:
- In Canvas: Courses → any course → Quizzes → Look for "Practice Quiz (LockDown Browser)"
- Or: Open LDB → it will load the Respondus splash page and check environment before any exam

**Expected baseline error (stock VM):**
```
"LockDown Browser has detected that this computer is running in a virtual machine environment.
Please use a physical computer to take this assessment."
```

**Key test:** Does the hardened VM show this error or proceed normally?

---

### Honorlock

**Acquisition:** Institution-provided Chrome extension + native application. Available through Canvas integration. Contact your university's online learning department.

**Installation in VM:**
1. Install Google Chrome in the VM
2. Navigate to an Honorlock-enabled exam in Canvas
3. Chrome will prompt to install the Honorlock extension
4. The extension installs the native companion application automatically

**Self-test:** Honorlock has an environment check page accessible from the Chrome extension icon. This runs all pre-exam checks without requiring an active exam session.

**Expected baseline error (stock VM):**
Honorlock typically blocks the session or flags it with a warning when VM artifacts are detected.

---

### Proctorio

**Acquisition:** Chrome extension only — available from Chrome Web Store if your institution uses it, or install directly (proctorio.com/extension).

**Installation in VM:**
1. Install Chrome in the VM
2. Install Proctorio Chrome extension
3. Navigate to a Proctorio-enabled exam

**Key test — WebGL renderer string (run BEFORE installing Proctorio):**
In Chrome DevTools console:
```javascript
const gl = document.createElement('canvas').getContext('webgl');
const ext = gl.getExtension('WEBGL_debug_renderer_info');
console.log(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL));
```
Record this string. If it contains "VirtIO", "SVGA", "llvmpipe", or "SwiftShader" — Proctorio will likely detect the VM.

---

## Supplementary Validation Tools

### Pafish
**Purpose:** Validates that CPUID, timing, registry, and disk checks pass before testing proctoring software.
**Source:** https://github.com/a0rtega/pafish
**Build:** `make -f Makefile.win64` (needs mingw-w64 on Linux) or download pre-built from releases

### VMAware
**Purpose:** Quantitative VM confidence score — use as a before/after metric.
**Source:** https://github.com/kernelwernel/VMAware
**Build:** `x86_64-w64-mingw32-g++ -std=c++17 -o vmaware.exe vmaware_test.cpp`

### HWiNFO64 (portable)
**Purpose:** Visually confirms SMBIOS shows Dell OptiPlex 7090 identity.
**Source:** hwinfo.com → Portable ZIP version (no install needed)

### CPU-Z (portable)
**Purpose:** Cross-checks CPUID and SMBIOS manufacturer/model fields.
**Source:** cpuid.com → ZIP (portable) version

### PowerShell WMI Audit Script
Run inside the VM to verify identity before testing proctoring software:
```powershell
Write-Host "=== WMI Identity Audit ===" -ForegroundColor Cyan
$cs = Get-WmiObject Win32_ComputerSystem
Write-Host "Manufacturer: $($cs.Manufacturer)"         # Expected: Dell Inc.
Write-Host "Model:        $($cs.Model)"                 # Expected: OptiPlex 7090

$bios = Get-WmiObject Win32_BIOS
Write-Host "BIOS Vendor:  $($bios.Manufacturer)"        # Expected: Dell Inc.
Write-Host "BIOS Version: $($bios.SMBIOSBIOSVersion)"   # Expected: 1.18.0

$gpu = Get-WmiObject Win32_VideoController
Write-Host "GPU:          $($gpu.Name)"                 # Expected: Intel(R) UHD Graphics 630

$nic = Get-WmiObject Win32_NetworkAdapter | Where-Object PhysicalAdapter
Write-Host "NIC:          $($nic.Name)"                 # Expected: Intel Ethernet
Write-Host "MAC:          $($nic.MACAddress)"            # Expected: 00:14:22:xx:xx:xx

$disk = Get-WmiObject Win32_DiskDrive
Write-Host "Disk:         $($disk.Model)"               # Expected: Samsung SSD 970 EVO Plus

$bat = Get-WmiObject Win32_Battery
Write-Host "Battery:      $($bat.Name)"                 # Expected: DELL-7DYG4 (from ACPI SSDT)
```
Save output as `detection-tests/screenshots/wmi-audit-hardened.txt`.

---

## Integrity Verification

Record binary SHA256 hashes here after download:

| Tool | Version | SHA256 | Date |
|---|---|---|---|
| LockDownBrowserSetup.exe | | | |
| Pafish.exe | | | |
| vmaware.exe | | | |
| HWiNFO64.exe | | | |
| cpuz_x64.exe | | | |
