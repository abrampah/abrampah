# Setup Guide — From Zero to Running Windows VM

This guide assumes you are new to QEMU/KVM and Linux virtualization.
Follow every step in order.

---

## What You Need Before Starting

| Item | Where to Get It |
|---|---|
| A Linux computer (bare-metal, not a VM) | Your own PC running Ubuntu/Debian |
| At least 8 GB RAM on the host | Check: `free -h` |
| At least 100 GB free disk space | Check: `df -h /` |
| A Windows 11 ISO | https://www.microsoft.com/en-us/software-download/windows11 |
| An internet connection | — |

> **Important:** This CANNOT run inside another VM (like VMware or VirtualBox on Windows).
> You need a real Linux install, either as your main OS or dual-boot.
> If you're on a laptop/desktop running Ubuntu — you're good.

---

## Step 1 — Install Required Software

Open a terminal and run:

```bash
sudo apt update
sudo apt install -y \
    qemu-system-x86 \
    qemu-utils \
    ovmf \
    acpica-tools \
    swtpm \
    bridge-utils \
    python3 \
    python3-pip \
    mesa-utils
```

Verify KVM works:
```bash
ls /dev/kvm
```
You should see `/dev/kvm`. If you get "No such file or directory", your CPU's virtualization is disabled in BIOS — restart, go into BIOS/UEFI, and enable "Intel VT-x" or "AMD-V".

---

## Step 2 — Download the Virtio Drivers ISO

VirtIO drivers make the VM hardware perform better. Download:
```bash
sudo mkdir -p /var/lib/libvirt/isos
cd /var/lib/libvirt/isos
sudo wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso
```

This is a ~600 MB download.

---

## Step 3 — Put the Windows ISO in Place

Download Windows 11 from Microsoft (link above — use the "Download Now" tool to get the ISO, or the Media Creation Tool). Once you have `Win11_23H2_English_x64.iso` (or similar), copy it:

```bash
sudo cp ~/Downloads/Win11_23H2_English_x64.iso /var/lib/libvirt/isos/
```

Rename it to match what `config.env` expects:
```bash
sudo mv /var/lib/libvirt/isos/Win11_*_x64.iso /var/lib/libvirt/isos/Win11_23H2_English_x64.iso
```

---

## Step 4 — Create the Virtual Hard Drive

This creates an 80 GB virtual disk file (it only uses space as needed, not all 80 GB immediately):

```bash
sudo mkdir -p /var/lib/libvirt/images
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/win11-stealth.qcow2 80G
```

---

## Step 5 — Edit the Config File

Open `vm/config.env` in the project:

```bash
nano /home/user/abrampah/vm/config.env
```

The defaults should already match what you've set up. Only change things if your file paths are different. The key lines to verify:

```
DISK_IMAGE="/var/lib/libvirt/images/win11-stealth.qcow2"     # matches Step 4
WIN_ISO="/var/lib/libvirt/isos/Win11_23H2_English_x64.iso"   # matches your ISO filename
VIRTIO_ISO="/var/lib/libvirt/isos/virtio-win.iso"            # matches Step 2
```

Save and exit: Ctrl+O, Enter, Ctrl+X.

---

## Step 6 — Set Up the Network (TAP Interface)

The VM needs a virtual network connection. Run once:

```bash
sudo ip tuntap add tap0 mode tap user $(whoami)
sudo ip link set tap0 up
```

Then run the MAC spoof script to set a Dell-branded network address:
```bash
sudo bash /home/user/abrampah/scripts/mac-spoof.sh tap0
```

---

## Step 7 — Start the TPM (Required for Windows 11)

Windows 11 needs a Trusted Platform Module. Run this before starting the VM:

```bash
mkdir -p /tmp/swtpm-state
swtpm socket \
    --tpmstate dir=/tmp/swtpm-state \
    --ctrl type=unixio,path=/tmp/swtpm-sock \
    --tpm2 \
    --daemon
```

The `--daemon` flag runs it in the background. Verify it started:
```bash
ls /tmp/swtpm-sock   # should show the socket file
```

---

## Step 8 — Build the ACPI Table

This creates a fake battery entry (makes the VM look like a laptop):

```bash
bash /home/user/abrampah/vm/acpi/build-acpi.sh
```

---

## Step 9 — First Boot: Install Windows

Now launch the VM for the first time. It will boot from the Windows ISO:

```bash
cd /home/user/abrampah
sudo bash vm/launch.sh
```

A window will open showing the Windows installer. Go through the install:

1. Select language → Next
2. "Install now"
3. When asked for a product key → click "I don't have a product key" (you can activate later or use an evaluation key)
4. Select "Windows 11 Pro"
5. Accept license → Next
6. Choose "Custom: Install Windows only (advanced)"
7. **You won't see a drive yet** — that's normal with NVMe. Click "Load driver":
   - Browse to the virtio-win CD drive (should be D: or E:)
   - Navigate to `vioscsi\w11\amd64\` and click OK
   - Select "Red Hat VirtIO SCSI controller" and click Next
   - Now you should see the 80 GB drive — select it and click Next
8. Windows installs and reboots several times (~20-30 minutes)

> During the out-of-box setup (after install), when it asks to connect to the internet — click "I don't have internet" / "Continue with limited setup" to create a local account instead of a Microsoft account.

---

## Step 10 — Install Remaining Drivers After Windows Boots

After Windows is fully installed and you're on the desktop:

1. Open File Explorer → navigate to the virtio-win CD drive
2. Find and run `virtio-win-guest-tools.exe` — this installs all drivers at once
3. Reboot when prompted

Your VM should now have working network, display, and storage drivers.

---

## Step 11 — Run the Registry Patch (Inside the VM)

This removes QEMU-identifying strings from the Windows registry.

1. In the VM, open File Explorer
2. Navigate to the virtio-win CD drive or copy `scripts/registry-patch.bat` into the VM via a shared folder
3. Right-click `registry-patch.bat` → "Run as administrator"
4. Click Yes on the UAC prompt
5. A black window will flash — that's the patch running
6. Reboot the VM

---

## Step 12 — Verify the VM Looks Like Real Hardware

Open PowerShell inside the VM and run:

```powershell
Get-WmiObject Win32_ComputerSystem | Select Manufacturer, Model
Get-WmiObject Win32_BIOS | Select Manufacturer, SMBIOSBIOSVersion
Get-WmiObject Win32_VideoController | Select Name
Get-WmiObject Win32_NetworkAdapter | Where PhysicalAdapter | Select Name, MACAddress
Get-WmiObject Win32_DiskDrive | Select Model
```

Expected output:
```
Manufacturer : Dell Inc.
Model        : OptiPlex 7090

Manufacturer : Dell Inc.
SMBIOSBIOSVersion : 1.18.0

Name : Intel(R) UHD Graphics 630

Name                              MACAddress
----                              ----------
Intel(R) PRO/1000 MT Desktop...  00:14:22:AB:CD:EF

Model : Samsung SSD 970 EVO Plus 1TB
```

If you see "QEMU", "VirtIO", or "Red Hat" anywhere — the registry patch didn't fully run. Re-run `registry-patch.bat` as Administrator and reboot.

---

## Step 13 — Test with Validation Tools

### Quick WebGL check (for Proctorio)

Inside the VM, open Chrome, press F12 (DevTools), go to the Console tab, and paste the contents of `scripts/webgl-check.js`. You should see a green "CLEAN" verdict.

### Pafish (general VM detection)

1. Download Pafish from https://github.com/a0rtega/pafish/releases
2. Run it inside the VM
3. All checks should show GREEN. Red items = still detected.

### Check with HWiNFO64

1. Download HWiNFO64 portable from https://www.hwinfo.com
2. Run it — the System Summary should show "Dell Inc. OptiPlex 7090"

---

## Step 14 — Install and Test Lockdown Browser

1. Go to your university's Respondus portal through Canvas
2. Download and install Respondus LockDown Browser inside the VM
3. Launch it
4. If it opens without showing a "virtual machine detected" error — the evasion worked
5. Screenshot everything for your paper

---

## Troubleshooting

| Problem | Fix |
|---|---|
| VM window doesn't open | Make sure you ran Steps 6 and 7 first |
| "No bootable device" | Verify WIN_ISO path in config.env; make sure the file exists |
| Windows doesn't see the hard drive | Load the vioscsi driver in Step 9 item 7 |
| Network doesn't work in VM | Re-run Steps 6 and the mac-spoof.sh script |
| LockDown Browser still detects VM | Re-run registry-patch.bat, reboot, check `Get-WmiObject Win32_ComputerSystem` |
| `/dev/kvm not found` | Enable Intel VT-x or AMD-V in BIOS, or: `sudo modprobe kvm_intel` |
| swtpm-sock not found | Re-run Step 7; check `pgrep swtpm` to see if it's running |

---

## After a Host Reboot

The TAP interface and swtpm don't survive host reboots. Before running the VM again:

```bash
# Re-create TAP interface
sudo ip tuntap add tap0 mode tap user $(whoami)
sudo ip link set tap0 up
sudo bash /home/user/abrampah/scripts/mac-spoof.sh tap0

# Re-start TPM
mkdir -p /tmp/swtpm-state
swtpm socket --tpmstate dir=/tmp/swtpm-state --ctrl type=unixio,path=/tmp/swtpm-sock --tpm2 --daemon

# Launch VM
cd /home/user/abrampah
sudo bash vm/launch.sh
```
