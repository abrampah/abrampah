# vm/config.windows.ps1 — Edit these paths before running launch.ps1

# Path to QEMU executable
# Download from: https://qemu.weilnetz.de/w64/
$QemuExe    = "C:\Program Files\qemu\qemu-system-x86_64.exe"
$QemuImg    = "C:\Program Files\qemu\qemu-img.exe"

# VM disk image location and size
$DiskImage      = "C:\VMs\win11-stealth.qcow2"
$DiskImageSizeGB = 80

# Windows 11 ISO — download from https://www.microsoft.com/en-us/software-download/windows11
$WinISO  = "C:\VMs\isos\Win11_23H2_English_x64.iso"

# VirtIO drivers ISO — download from:
# https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso
$VirtioISO = "C:\VMs\isos\virtio-win.iso"

# OVMF (UEFI firmware) — single-file mode (-bios flag)
# edk2-x86_64-vars.fd is not included in the QEMU Windows package,
# so we use the secure-code file directly as a BIOS image instead.
$OvmfBios = "C:\Program Files\qemu\share\edk2-x86_64-secure-code.fd"

# VM resources
$VmRam            = "8G"
$VmCores          = 4
$VmSockets        = 1
$VmCoresPerSocket = 2
$VmThreads        = 2

# Network — Dell OUI MAC prefix. Change last 3 pairs to anything (e.g., AA:BB:CC)
$MacAddr = "00:14:22:AA:BB:CC"

# Enable fake battery ACPI table (requires iasl to be installed)
$StealthAcpi = $true
