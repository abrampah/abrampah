# Process and Service Artifact Evasion

## A — Detection Vector

VM guest additions and integration services create running processes and Windows services that are directly observable:

**Process enumeration:**
```c
// Snapshot of running processes
HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
PROCESSENTRY32 pe;
pe.dwSize = sizeof(pe);
Process32First(hSnap, &pe);
do {
    if (strstr(pe.szExeFile, "vmtoolsd") ||  // VMware Tools daemon
        strstr(pe.szExeFile, "VBoxService") || // VirtualBox
        strstr(pe.szExeFile, "VBoxTray") ||
        strstr(pe.szExeFile, "qemu-ga")) {     // QEMU guest agent
        // VM detected
    }
} while (Process32Next(hSnap, &pe));
```

**Service enumeration via WMI:**
```powershell
Get-Service | Where-Object { $_.Name -match "vmtools|vbox|qemu|virtio|balloon" }
```

**Named pipe and device enumeration:**
VMware Tools creates named pipes like `\\.\HGFS` (host-guest file sharing). Detection tools check for these pipe names.

## B — Why It Reveals a VM

Guest additions install services that run continuously to provide functionality:
- VMware: `vmtoolsd.exe` (tools daemon), `vmwaretray.exe` (status icon)
- VirtualBox: `VBoxService.exe` (time sync, shared clipboard), `VBoxTray.exe`
- QEMU: `qemu-ga.exe` (guest agent, optional), VirtIO balloon service

These processes serve legitimate purposes (improved performance, shared clipboard, time synchronization) but are also obvious VM indicators.

## C — Evasion Implementation

**Primary strategy: don't install guest additions.**

Our setup uses:
- No VMware Tools (we're not using VMware)
- No VirtualBox Guest Additions
- No QEMU Guest Agent executable in the guest (the guest agent channel in `windows-stealth.xml` can be removed)

The VirtIO drivers we install provide storage and network functionality but do NOT require running `vmtoolsd.exe` or similar processes. The VirtIO driver model is a kernel driver, not a user-space daemon.

**VirtIO balloon service:**
The memory balloon driver (`Balloon` service) runs as a kernel service (not a process visible to user space process enumeration). After `registry-patch.ps1` removes its service key, it won't restart after reboot.

In `windows-stealth.xml`, balloon is disabled:
```xml
<memballoon model="none"/>
```

**QEMU guest agent:**
The XML includes a `channel` for the guest agent (for convenience during setup), but the agent binary `qemu-ga.exe` is not installed in the guest by default. The channel on the host side doesn't expose anything to guest process enumeration.

**Named pipe check:**
With no VMware or VirtualBox installed, `\\.\HGFS`, `\\.\vmci`, and `\\.\VBoxMiniRdrDN` pipes don't exist.

**Verification:**
```powershell
# Should return empty or only legitimate Windows processes
Get-Process | Where-Object { $_.Name -match "vmware|vbox|qemu|virtio" }
Get-Service | Where-Object { $_.Name -match "vmware|vbox|qemu|virtio|balloon" }
```

## D — Defensive Implications

Process and service enumeration is effective against careless VM setups (those with full guest additions installed) but is the weakest category of detection:
- Any informed user configures their VM without guest additions if they care about evasion
- Malware that only checks for known process names is easily defeated by renaming or not installing

More sophisticated process-based detection:
- **Parent process anomalies:** In VMs, some processes have unexpected parent processes. For example, `csrss.exe` spawned by an unusual parent, or processes with `ntoskrnl.exe` as parent via unusual paths.
- **Process hollowing traces:** Some VMs run with different process address space layouts than real hardware (ASLR entropy differs under some hypervisors).
- **Undocumented process handles:** Hypervisor-injected code (like VMware's backdoor handler) leaves open handles that can be enumerated with NtQuerySystemInformation.

In practice, the absence of guest additions means this entire detection category is defeated with minimal effort.
