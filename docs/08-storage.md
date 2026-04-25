# Storage Device String Spoofing

## A — Detection Vector

WMI exposes storage device identity strings that originate from the disk firmware (or emulated firmware in a VM):

```powershell
Get-WmiObject Win32_DiskDrive | Select-Object Model, SerialNumber, FirmwareRevision

# QEMU default output:
# Model: QEMU HARDDISK
# SerialNumber: QM00001
# FirmwareRevision: 2.5+
```

Pafish checks `Win32_DiskDrive.Model` for substrings:
- `VBOX HARDDISK`
- `QEMU HARDDISK`
- `VMWARE VIRTUAL IDE HARD DRIVE`
- `VIRTUAL HD`

Al-Khaser additionally checks `Win32_DiskDrive.SerialNumber` for obviously fake patterns.

## B — Why It Reveals a VM

QEMU's default block device (virtio-blk or IDE) reports generic model strings set in QEMU source code. The strings were chosen for clarity in development environments, not concealment.

VirtIO block devices (`-drive ...,if=virtio`) report through a different WMI interface (`Win32_DiskDrive` via the VirtIO SCSI driver) and also expose the driver name in the device stack.

## C — Evasion Implementation

**NVMe device with Samsung model string:**

```bash
-drive file="${DISK_IMAGE}",format=qcow2,if=none,id=drive0,cache=writeback,discard=unmap
-device nvme,drive=drive0,serial="S4EWNX0R123456",model="Samsung SSD 970 EVO Plus 1TB"
```

QEMU's NVMe device emulation allows arbitrary `serial` and `model` strings. These appear directly in:
- `Win32_DiskDrive.Model` = "Samsung SSD 970 EVO Plus 1TB"
- `Win32_DiskDrive.SerialNumber` = "S4EWNX0R123456"

The NVMe PCI device ID used by QEMU does not expose a VM-specific vendor ID — NVMe is a standard interface without vendor-specific PCI IDs in the way VirtIO has.

**Consistency check:**
The chosen model string should be consistent with the rest of the machine identity:
- Dell OptiPlex 7090 was sold with Samsung 970 EVO Plus SSDs — this is a realistic combination
- The serial number format `S4EWNX0R123456` matches Samsung's serial pattern for this drive family

## D — Defensive Implications

Storage spoofing via device model strings is straightforward and effective because:
- QEMU's NVMe emulation passes model/serial strings directly from the command line to the Windows driver
- There is no cryptographic binding between the model string and actual drive behavior

**Residual artifacts:**
- **SMART data:** A real Samsung SSD would return specific SMART vendor attributes via `IOCTL_STORAGE_QUERY_PROPERTY`. QEMU's NVMe emulation returns minimal or zeroed SMART data, which is unrealistic for a "2-year-old SSD."
- **Wear indicators:** Real SSDs report power-on hours, total bytes written, and wear level indicators via SMART. A VM with zero hours and zero writes is suspicious.
- **I/O timing:** SSD read/write latency under load follows characteristic patterns. A qcow2 image stored on HDD will have different timing than a real NVMe SSD.

**For advanced sandbox detection:**
Querying SMART data (`Win32_DiskDrive` doesn't expose it — need DeviceIoControl with SMART commands) would reveal the unrealistic SMART values. This is rarely done by commodity malware but represents a detection avenue for sophisticated threats.
