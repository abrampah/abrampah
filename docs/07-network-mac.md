# Network MAC Address Spoofing

## A — Detection Vector

Every network interface has a MAC (Media Access Control) address. The first 3 bytes (OUI — Organizationally Unique Identifier) identify the hardware manufacturer. VM platforms use reserved OUI prefixes:

| OUI | Manufacturer |
|---|---|
| `52:54:00` | QEMU/KVM (libvirt default) |
| `08:00:27` | VirtualBox (Intel PRO/1000 MT Desktop) |
| `00:0C:29` | VMware Workstation |
| `00:50:56` | VMware ESX/ESXi |
| `00:15:5D` | Microsoft Hyper-V |

Detection tools check the NIC's MAC OUI via WMI:
```powershell
Get-WmiObject Win32_NetworkAdapter | 
    Where-Object PhysicalAdapter | 
    Select-Object MACAddress
# 52:54:00:XX:XX:XX → QEMU detected
```

Pafish specifically checks for these OUI prefixes and flags them as VM indicators.

## B — Why It Reveals a VM

QEMU's default TAP-based networking assigns MAC addresses starting with `52:54:00` — a prefix allocated to QEMU. This is done for convenience in virtual network setups (no risk of MAC collision with real hardware on the same segment).

This prefix is not present in any real hardware. Its presence is an immediate and trivial VM indicator.

## C — Evasion Implementation

**`scripts/mac-spoof.sh`** sets the TAP interface MAC to a Dell OUI prefix before the VM starts:

```bash
sudo bash scripts/mac-spoof.sh tap0
```

The script uses Dell Inc. OUI prefixes:
- `00:14:22` — most common Dell desktop OUI
- `00:21:70`, `00:22:19`, `B8:CA:3A`, `F8:DB:88`

The MAC is also set in `vm/launch.sh` and `vm/windows-stealth.xml`:
```bash
-device e1000e,netdev=net0,mac=00:14:22:AB:CD:EF
```
```xml
<mac address="00:14:22:ab:cd:ef"/>
```

**Device model consistency:**
The NIC model (`e1000e`) must be consistent with the MAC OUI. An Intel I219-V NIC with a Dell MAC address is realistic — Dell OptiPlex 7090 ships with the Intel I219-V.

Using VirtIO NIC with a Dell MAC would be inconsistent: the driver name would reveal Red Hat/VirtIO while the MAC claims Dell hardware.

## D — Defensive Implications

MAC spoofing is trivial to implement and trivial to detect at a slightly deeper level:

**Beyond OUI:**
- **Driver mismatch:** If the WMI NIC name says "Intel I219-V" but the PCI device ID is `1AF4:xxxx` (Red Hat), the OUI and driver name are inconsistent with each other.
- **PCI subvendor ID:** The PCI configuration space includes a subsystem vendor ID (SVID). For a real Dell Intel I219-V, the SVID would be `0x1028` (Dell). QEMU's e1000e emulation may not set this correctly.
- **Network traffic fingerprinting:** VMs typically have lower-jitter network timing than physical machines behind real NICs with hardware interrupt coalescing and DMA.

**Practical defense:**
Most current detection tools only check the OUI, making MAC spoofing effective against them. More sophisticated analysis would require correlating MAC, driver name, PCI IDs, and network timing — a combination that is much harder to fake simultaneously.
