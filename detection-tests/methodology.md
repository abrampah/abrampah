# Detection Test Methodology

## Purpose

This document describes the exact procedure for running VM detection tools against the baseline (unmodified) and hardened (all evasion techniques applied) VM configurations. The incremental approach — applying one technique at a time — isolates which technique defeats which specific check.

## Test Environment

| Component | Value |
|---|---|
| Host OS | Ubuntu 24.04 LTS (bare-metal KVM required) |
| Hypervisor | QEMU 8.2.x / KVM |
| Guest OS | Windows 11 Pro 23H2 (64-bit) |
| QEMU machine type | q35 |
| VM RAM | 8 GB |
| VM vCPUs | 4 (2 cores × 2 threads) |

## Tool Versions and Acquisition

See `tools-reference.md` for exact source URLs, build instructions, and SHA256 hashes.

| Tool | Version Tested | Run Location |
|---|---|---|
| Pafish | latest from git | Guest (Windows) |
| Al-Khaser | latest from git | Guest (Windows) |
| VMAware | latest from git | Guest (Windows) |
| CPU-Z | latest portable | Guest (Windows) |
| HWiNFO64 | latest portable | Guest (Windows) |
| WMI Explorer | latest portable | Guest (Windows) |

## Test Phases

### Phase 1 — Baseline (no evasion)

**Setup:**
1. Launch QEMU with only basic parameters (no `-cpu` tricks, no `-smbios`, no timing flags)
2. Install Windows 11 with default virtio drivers (NOT patched with driver-rename.py)
3. Do NOT run registry-patch.ps1
4. Take a snapshot named `baseline` before running tools

**Execution:**
1. Copy all tool binaries into the VM via shared drive or SMB
2. Run Pafish.exe — screenshot all output; note RED (detected) vs GREEN (not detected) items
3. Run al-khaser.exe — screenshot; note detected items
4. Run VMAware-test.exe — note confidence percentage
5. Open CPU-Z, HWiNFO64 — screenshot SMBIOS/manufacturer fields
6. Run custom WMI query (see below) — screenshot output

**WMI query for baseline documentation:**
```powershell
Get-WmiObject Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory
Get-WmiObject Win32_BIOS | Select-Object Manufacturer, Version, SMBIOSBIOSVersion
Get-WmiObject Win32_VideoController | Select-Object Name, DriverVersion
Get-WmiObject Win32_NetworkAdapter | Where-Object {$_.PhysicalAdapter} | Select-Object Name, MACAddress
Get-WmiObject Win32_DiskDrive | Select-Object Model, SerialNumber
```

5. Document all results in `results-baseline.md`

### Phase 2 — Incremental Hardening

Apply techniques in this order (each depends on the previous being stable):

| Step | Technique | Expected New Passes |
|---|---|---|
| 1 | CPUID: `hypervisor=off`, `kvm=off` | Pafish CPUID checks, KVM leaf checks |
| 2 | Timing: `+invtsc`, disable HPET/kvmclock | Pafish/Al-Khaser timing checks |
| 3 | SMBIOS: all `-smbios type=N` flags | HWiNFO manufacturer, WMI Win32_BIOS |
| 4 | ACPI: fake battery SSDT | Battery presence check |
| 5 | Storage: NVMe Samsung model string | WMI Win32_DiskDrive model check |
| 6 | Network: Dell OUI MAC | MAC prefix check |
| 7 | Driver INF rename (driver-rename.py) | Win32_NetworkAdapter name |
| 8 | Registry patch (registry-patch.ps1) | Service enumeration checks |
| 9 | UEFI (OVMF vs SeaBIOS) | BIOS vendor string check |

**For each step:**
1. Modify `vm/launch.sh` to add only the new technique
2. Reboot or recreate the VM from snapshot
3. Run the full tool suite
4. Record delta in `results-matrix.csv` — which checks changed from FAIL→PASS
5. Screenshot the changed tool output in `screenshots/step-N-technique-name/`

### Phase 3 — Fully Hardened

All techniques applied simultaneously:
1. Use the complete `vm/launch.sh` as committed
2. Run `scripts/driver-rename.py` on virtio drivers before install
3. Run `scripts/registry-patch.ps1` after install
4. Full tool suite run
5. Document remaining DETECTED items — these are expected research findings

### Phase 4 — Custom Adversarial Detector

Write `custom-detector.py` (Windows, runs with Python for Windows) to attempt to catch inconsistencies introduced by our spoofing:

```python
# Check 1: SMBIOS says Dell OptiPlex but no battery (physical OptiPlex is desktop, no battery)
# Actually this is our fake battery SSDT — so this should now be consistent.

# Check 2: MAC address Dell OUI but NIC model might be e1000e (Intel) — consistent.

# Check 3: CPU says i7-10700 but CPUID leaf 4 (cache topology) may differ from real hardware.

# Check 4: SMBIOS board product is "0TT6JF" — verify this is a real Dell board part number.

# Check 5: Check for timing inconsistency — RDTSC delta over CPUID barrier > threshold.
```

This adversarial check helps quantify the quality of the evasion and identifies remaining attack surface.

## Recording Results

All results go into `results-matrix.csv` with the schema:
```
tool,version,technique_category,check_name,baseline_result,hardened_result,notes
```

Values for result columns: `DETECTED`, `NOT_DETECTED`, `N/A`, `ERROR`

## Screenshots Convention

Save screenshots as:
```
screenshots/
  baseline/
    pafish-baseline.png
    al-khaser-baseline.png
    hwinfo-smbios-baseline.png
  step-01-cpuid/
    pafish-after-cpuid-hide.png
  step-07-registry/
    al-khaser-after-registry-patch.png
  hardened-final/
    pafish-final.png
    al-khaser-final.png
    hwinfo-smbios-final.png
```
