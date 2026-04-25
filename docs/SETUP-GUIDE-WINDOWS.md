# Windows Setup Guide — Running the Stealth VM on Windows 10/11

This guide is for running the research VM on a **Windows host** (no Linux needed).

---

## How It Works on Windows

On Linux we use **KVM** for fast virtualization. On Windows the equivalent is called
**WHPX** (Windows Hypervisor Platform) — it's built into Windows 10/11 Pro and uses
the same underlying CPU virtualization hardware.

QEMU runs natively on Windows and accepts almost all the same anti-detection flags.
The only real difference: networking is simpler on Windows (no TAP driver needed).

---

## Requirements

| Item | Requirement |
|---|---|
| Windows version | Windows 10 Pro/Enterprise or Windows 11 Pro (Home works but is harder) |
| RAM | 16 GB recommended (8 GB minimum — 8 for host + 8 for VM) |
| Disk space | 100+ GB free |
| CPU | Intel or AMD with virtualization support (VT-x / AMD-V) |
| Internet | For downloading software |

> **Home edition users:** WHPX is available but Hyper-V is not. Follow the
> "Enable WHPX without Hyper-V" section below.

---

## Step 1 — Enable Windows Hypervisor Platform

This is what gives QEMU hardware-accelerated speed on Windows.

1. Press `Win + R`, type `optionalfeatures`, press Enter
2. Scroll down and check both:
   - **Hyper-V** (all sub-items)
   - **Windows Hypervisor Platform**
3. Click OK and restart when prompted

**Verify it worked** — open PowerShell and run:
```powershell
(Get-WmiObject Win32_ComputerSystem).HypervisorPresent
```
Should return `True`.

> **If you're on Windows 10/11 Home:** Hyper-V isn't available, but WHPX alone works.
> Run this in an Administrator PowerShell to enable just WHPX:
> ```powershell
> dism /online /enable-feature /featurename:HypervisorPlatform /all /norestart
> Restart-Computer
> ```

---

## Step 2 — Install QEMU for Windows

1. Go to **https://qemu.weilnetz.de/w64/**
2. Download the latest `.exe` installer (e.g., `qemu-w64-setup-20240813.exe`)
3. Run it — accept defaults, install to `C:\Program Files\qemu\`
4. Add QEMU to your PATH:
   - Search "Edit environment variables" → System variables → Path → Edit → New
   - Add: `C:\Program Files\qemu`
   - Click OK on all dialogs

**Verify:**
```powershell
qemu-system-x86_64.exe --version
```
Should print the QEMU version number.

---

## Step 3 — Download the ISOs

Create a folder for VM files:
```powershell
New-Item -ItemType Directory -Path C:\VMs\isos -Force
New-Item -ItemType Directory -Path C:\VMs\nvram -Force
```

**Windows 11 ISO:**
- Go to https://www.microsoft.com/en-us/software-download/windows11
- Click "Download Now" under "Create Windows 11 Installation Media"
- Run the tool, choose "ISO file", save it to `C:\VMs\isos\Win11_23H2_English_x64.iso`

**VirtIO Drivers ISO** (makes VM hardware work properly):
```powershell
# Download in PowerShell:
Invoke-WebRequest `
    -Uri "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso" `
    -OutFile "C:\VMs\isos\virtio-win.iso"
```
Or just open the URL in your browser and save it.

---

## Step 4 — Create the Virtual Hard Drive

```powershell
qemu-img create -f qcow2 C:\VMs\win11-stealth.qcow2 80G
```

---

## Step 5 — Edit the Config File

Open the file `vm\config.windows.ps1` in Notepad:
```powershell
notepad C:\path\to\abrampah\vm\config.windows.ps1
```

Verify these paths match what you created:
```powershell
$QemuExe    = "C:\Program Files\qemu\qemu-system-x86_64.exe"
$DiskImage  = "C:\VMs\win11-stealth.qcow2"
$WinISO     = "C:\VMs\isos\Win11_23H2_English_x64.iso"
$VirtioISO  = "C:\VMs\isos\virtio-win.iso"
```

Find the OVMF firmware files — QEMU ships them but they may have different names:
```powershell
Get-ChildItem "C:\Program Files\qemu\share\" -Filter "*.fd"
```
You'll see files like `edk2-x86_64-code.fd` and `edk2-x86_64-vars.fd`.
Update `$OvmfCode` and `$OvmfVarsTemplate` in config if the names differ.

---

## Step 6 — Handle Windows 11 TPM Requirement

Windows 11 requires a TPM chip. You have two options:

### Option A — Install swtpm (software TPM)
1. Download swtpm for Windows from https://github.com/stefanberger/swtpm/releases
2. Install it and make sure `swtpm` is in your PATH
3. The `launch.ps1` script will start it automatically

### Option B — Bypass the TPM check (simpler)
During Windows installation, when you hit the "This PC can't run Windows 11" screen:
1. Press **Shift + F10** to open a command prompt
2. Type:
   ```
   reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
   reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
   reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f
   ```
3. Close the command prompt and click the back arrow, then try again

### Option C — Install Windows 10 instead
Windows 10 has no TPM requirement and works identically for this research.
Use a Windows 10 ISO and pass `-NoTPM` to `launch.ps1`.

---

## Step 7 — First Boot: Install Windows

Open **PowerShell as Administrator** and run:

```powershell
cd C:\path\to\abrampah
.\vm\launch.ps1 -InstallMode
```

A QEMU window opens showing the Windows installer. Follow these steps:

1. Select language → **Next**
2. **Install now**
3. No product key? → **"I don't have a product key"**
4. Select **Windows 11 Pro** (or Windows 10 Pro)
5. Accept license → **Next**
6. **Custom: Install Windows only (advanced)**
7. **No drive appears?** — This is normal. Click **Load driver**:
   - Browse to the VirtIO CD drive (D: or E:)
   - Navigate to `vioscsi\w11\amd64\` (or `w10\amd64\` for Windows 10)
   - Click **OK** → select **"Red Hat VirtIO SCSI controller"** → **Next**
   - Now the 80 GB drive appears — select it → **Next**
8. Wait 20–30 minutes for Windows to install and reboot

**During setup wizard after install:**
- When it asks to sign in with a Microsoft account, click:
  **"Sign-in options"** → **"Offline account"** → **"Skip for now"**
- Create a local username and password

---

## Step 8 — Install VirtIO Drivers

After you're on the Windows desktop inside the VM:

1. Open **File Explorer** → find the VirtIO CD drive (D: or E:)
2. Run **`virtio-win-guest-tools.exe`** — installs all drivers at once
3. **Restart** when prompted

---

## Step 9 — Run the Registry Patch

This removes QEMU-identifying strings from the registry.

Option A — Copy the file into the VM:
- The VM has user-mode networking, so internet works
- Open a browser in the VM and access your repo, or use a USB drive

Option B — Run directly if you map a network share:
Inside the VM, right-click `registry-patch.bat` → **Run as administrator** → Yes

Then **restart the VM**.

---

## Step 10 — Verify the VM Looks Like Real Hardware

Inside the VM, open **PowerShell** and run:
```powershell
Get-WmiObject Win32_ComputerSystem | Select Manufacturer, Model
Get-WmiObject Win32_BIOS | Select Manufacturer, SMBIOSBIOSVersion
Get-WmiObject Win32_VideoController | Select Name
Get-WmiObject Win32_DiskDrive | Select Model
```

Expected:
```
Manufacturer : Dell Inc.        Model : OptiPlex 7090
Manufacturer : Dell Inc.        SMBIOSBIOSVersion : 1.18.0
Name : Intel(R) UHD Graphics 630
Model : Samsung SSD 970 EVO Plus 1TB
```

If you see QEMU, VirtIO, or Red Hat — re-run `registry-patch.bat` and reboot.

---

## Step 11 — Test with Lockdown Browser

1. In the VM, go to your university's Canvas → Respondus portal
2. Download and install **LockDown Browser**
3. Launch it
4. **Goal:** it opens without showing a "Virtual Machine Detected" error

If it passes → take screenshots → that's the core result for your paper.

---

## Launching the VM After Initial Setup

Once Windows is installed, run without `-InstallMode`:
```powershell
cd C:\path\to\abrampah
.\vm\launch.ps1
```

### Useful flags:
```powershell
.\vm\launch.ps1                    # Normal stealth mode
.\vm\launch.ps1 -NoStealth         # Baseline mode (stock VM, no anti-detection)
.\vm\launch.ps1 -NoTPM             # Skip TPM (if swtpm not installed)
.\vm\launch.ps1 -InstallMode       # Force boot from ISO
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| QEMU opens but immediately closes | Check PowerShell output — usually an error in a flag or missing file |
| "WHPX not available" warning | Enable Hyper-V/WHPX in Windows Features (Step 1), reboot |
| Runs very slowly ("TCG" in output) | WHPX is not enabled — see Step 1 |
| No hard drive in Windows installer | Load vioscsi driver from VirtIO CD (Step 7, item 7) |
| Windows 11 says "Can't run on this PC" | Do the TPM bypass in Step 6 Option B |
| VM still detected by LockDown Browser | Re-run `registry-patch.bat` as Administrator, reboot |
| Network not working in VM | User-mode networking should work out of the box — try pinging 8.8.8.8 |
| Black screen after first reboot | Normal — Windows is finishing install. Wait 2–3 minutes |

---

## Known Limitation on Windows Host

**WebGL renderer (relevant for Proctorio only):**
On Windows, QEMU does not support OpenGL passthrough (virgl) to the guest.
The WebGL renderer inside Chrome will show a VirtIO string.

For Proctorio testing, GPU passthrough via IOMMU (VFIO) would solve this,
but that requires Linux. For Respondus LockDown Browser and Honorlock,
this does not matter — they don't check WebGL.

If Proctorio is your target, note this limitation in your paper and explain
that it requires a Linux host with a dedicated GPU for full evasion.
