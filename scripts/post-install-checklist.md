# Post-Install Checklist

Follow these steps in order after Windows 11 installation is complete.
Complete each step before moving to the next.

---

## Step 1: Install VirtIO Drivers (if using VirtIO devices)

If you installed the patched virtio-win drivers (`driver-rename.py` was run first):
- Open Device Manager — any devices with yellow exclamation marks need drivers
- Browse to the virtio-win ISO (drive D:) for each driver
- Install: storage controller, NIC, balloon (optional), input, RNG

Verify in Device Manager:
- [ ] Network adapter shows "Intel(R) Ethernet Connection I219-V" (not Red Hat)
- [ ] No yellow exclamation marks remain

---

## Step 2: Configure Display Resolution

Set a realistic resolution:
- Right-click Desktop → Display Settings
- Resolution: 1920×1080 minimum (3840×2160 if VM display supports it)
- [ ] Resolution set to 1920×1080 or higher

---

## Step 3: Disable Windows Update (temporary)

Windows Update may reinstall original driver strings. Disable during testing:
- Open Services (services.msc)
- Find "Windows Update" → Right-click → Properties → Startup type: Disabled → Stop

Or via PowerShell:
```powershell
Stop-Service wuauserv
Set-Service wuauserv -StartupType Disabled
```
- [ ] Windows Update disabled

---

## Step 4: Copy Patching Scripts to VM

Copy the `scripts/` folder into the VM via:
- Shared folder (if configured)
- USB drive image
- QEMU `virtfs` / 9p filesystem

Place scripts in `C:\tools\` for easy access.

---

## Step 5: Run Registry Patch (as Administrator)

Double-click `registry-patch.bat` OR:
```
Right-click registry-patch.bat → Run as administrator
```

Review the log file path shown at the end.

- [ ] Registry patch completed without errors
- [ ] Change log saved (note the path shown)

---

## Step 6: Reboot

Reboot the VM to ensure all driver removals take effect.
- [ ] VM rebooted

---

## Step 7: Verify WMI Identity

Open PowerShell as Administrator and run:
```powershell
Get-WmiObject Win32_ComputerSystem | Select Manufacturer, Model
Get-WmiObject Win32_BIOS | Select Manufacturer, SMBIOSBIOSVersion
Get-WmiObject Win32_VideoController | Select Name
Get-WmiObject Win32_NetworkAdapter | Where-Object PhysicalAdapter | Select Name, MACAddress
Get-WmiObject Win32_DiskDrive | Select Model, SerialNumber
Get-WmiObject Win32_Battery | Select Name, BatteryStatus
```

Expected output:
```
Win32_ComputerSystem: Manufacturer=Dell Inc., Model=OptiPlex 7090
Win32_BIOS: Manufacturer=Dell Inc., SMBIOSBIOSVersion=1.18.0
Win32_VideoController: Name=Intel(R) UHD Graphics 630  (or similar)
Win32_NetworkAdapter: MACAddress=00:14:22:xx:xx:xx
Win32_DiskDrive: Model=Samsung SSD 970 EVO Plus 1TB
Win32_Battery: (should return battery entry)
```

- [ ] All WMI fields match expected values

---

## Step 8: Verify in HWiNFO64

Run HWiNFO64.exe (portable, no install needed):
- [ ] System Summary: Manufacturer = Dell Inc.
- [ ] System Summary: Product = OptiPlex 7090
- [ ] SMBIOS Type 0: BIOS Vendor = Dell Inc.
- [ ] SMBIOS Type 17: Memory Manufacturer = Samsung

---

## Step 9: Take Baseline Screenshot

Before running any detection tools:
- Take a screenshot showing HWiNFO64 SMBIOS view
- Save as `detection-tests/screenshots/hardened-final/hwinfo-before-tools.png`

---

## Step 10: Take Snapshot

On the host, run:
```bash
bash scripts/snapshot.sh post-patch-clean "All anti-detection patches applied"
```
- [ ] Snapshot created

---

## Step 11: Run Detection Tools

Follow `detection-tests/methodology.md` Phase 3.
- [ ] Pafish run, screenshot saved
- [ ] Al-Khaser run, screenshot saved
- [ ] VMAware run, score recorded
- [ ] results-matrix.csv updated
- [ ] results-hardened.md filled in

---

## Notes

- If a detection tool crashes or hangs, note it in the results with reason "ERROR"
- Some Pafish checks require specific conditions (e.g., the user must not move the mouse during timing tests)
- Run detection tools as a normal user (not Administrator) to match real malware execution context
- Disable antivirus during testing (Pafish and Al-Khaser may be flagged as malware)
