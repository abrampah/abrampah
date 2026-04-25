# Windows VM Indistinguishability from Physical Hardware

**MS Networks and Cybersecurity — University of New Haven**

## Research Purpose

This project documents techniques for configuring a QEMU/KVM-based Windows VM to minimize detectable VM artifacts. The goal is academic: understanding how malware detects sandboxes enables defenders to build better analysis environments and detection systems.

Each technique is documented with:
- The detection vector it defeats
- Why the artifact exists in a VM vs. physical hardware
- The evasion implementation
- Defensive implications for sandbox/AV authors

## Host Requirements

> **IMPORTANT:** KVM hardware virtualization is required. The host must be **bare-metal Linux** with `/dev/kvm` present.
>
> If running on a cloud instance, enable nested virtualization first:
> ```bash
> # Intel hosts
> modprobe kvm_intel nested=1
> echo "options kvm_intel nested=1" >> /etc/modprobe.d/kvm.conf
> # AMD hosts
> modprobe kvm_amd nested=1
> echo "options kvm_amd nested=1" >> /etc/modprobe.d/kvm.conf
> ```
> Verify: `cat /sys/module/kvm_intel/parameters/nested` should return `Y`.

## Software Dependencies

```bash
# Ubuntu/Debian
sudo apt install -y qemu-system-x86 qemu-utils ovmf libvirt-daemon-system \
    virtinst iasl bridge-utils python3 python3-pip

pip3 install -r requirements.txt
```

Also download **virtio-win ISO** from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/

## Quick Start

1. **Edit `vm/config.env`** — set paths for your disk image, Windows ISO, virtio-win ISO, and OVMF firmware.

2. **Build the fake battery ACPI table:**
   ```bash
   bash vm/acpi/build-acpi.sh
   ```

3. **Patch VirtIO driver strings** (run before Windows install):
   ```bash
   # Mount virtio-win ISO and run:
   python3 scripts/driver-rename.py /mnt/virtio-win/
   ```

4. **Set up network bridge** (one-time):
   ```bash
   sudo ip link add br0 type bridge
   sudo ip link set br0 up
   sudo ip tuntap add tap0 mode tap
   sudo ip link set tap0 master br0
   sudo ip link set tap0 up
   ```

5. **Spoof MAC address before launch:**
   ```bash
   sudo bash scripts/mac-spoof.sh tap0
   ```

6. **Launch the VM:**
   ```bash
   sudo bash vm/launch.sh
   ```

7. **After Windows install**, run inside the guest (as Administrator):
   ```
   registry-patch.bat
   ```
   Then follow `scripts/post-install-checklist.md`.

8. **Take a clean snapshot** after patching:
   ```bash
   bash scripts/snapshot.sh
   ```

## Repository Structure

```
vm/                     QEMU launch script, libvirt XML, ACPI and EDID sources
scripts/                Host-side and guest-side patching scripts
detection-tests/        Test methodology, baseline and hardened results, tool reference
docs/                   Per-technique academic documentation
```

## Detection Tools Used

| Tool | Source |
|---|---|
| Pafish | https://github.com/a0rtega/pafish |
| Al-Khaser | https://github.com/LordNoteworthy/al-khaser |
| VMAware | https://github.com/kernelwernel/VMAware |
| CPU-Z | https://www.cpuid.com/softwares/cpu-z.html |
| HWiNFO64 | https://www.hwinfo.com/ |

## Academic References

- Raffetseder, Kruegel, Kirda (2007). "Detecting System Emulators." *ISC 2007.*
- Garfinkel, Adams, Warfield, Franklin (2007). "Compatibility is Not Transparency: VMM Detection Myths and Realities." *HotOS XI.*
- Branco, Barbosa, Neto (2012). "Scientific but Not Academical Overview of Malware Anti-Debugging, Anti-Disassembly and Anti-VM Technologies." *Black Hat USA.*
- Ligh, Case, Levy, Walters (2014). *The Art of Memory Forensics.* Wiley.

## License

Academic use only. All scripts and configurations are provided for educational and research purposes.
