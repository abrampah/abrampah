# Academic Proctoring Software Security Evaluation

## VM Indistinguishability as a Research Platform

**MS Networks and Cybersecurity — University of New Haven**

## Research Purpose

This project evaluates whether academic proctoring and lockdown browser software — such as **Respondus LockDown Browser**, **Honorlock**, **ProctorU**, and **Proctorio** — can reliably detect that an exam is being taken inside a virtual machine.

These tools are widely deployed at universities with the claim that they enforce exam integrity by preventing access to unauthorized resources. A core assumption of that claim is that the software can detect virtualization. If a sufficiently configured VM is undetectable, the security guarantee fails — the student could run a second OS in the VM while the lockdown browser runs on the host, or vice versa.

**This is an academic integrity research question, not a malware evasion project.** The techniques documented here are evaluated against proctoring software to determine whether their VM detection provides genuine security or security theater. Published academic literature (cited throughout) covers this topic directly.

Each technique is documented with:
- The detection vector it defeats
- Why the artifact exists in a VM vs. physical hardware
- The evasion implementation
- Implications for proctoring software vendors and university IT policy

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

## Primary Research Target: Lockdown Browser Software

The primary evaluation targets are proctoring/lockdown browser applications:

| Software | Vendor | Deployment |
|---|---|---|
| Respondus LockDown Browser | Respondus Inc. | Most widely used in US universities |
| Honorlock | Honorlock Inc. | Common in Canvas LMS |
| Proctorio | Proctorio Inc. | Chrome extension-based |
| ProctorU | Meazure Learning | Live + automated proctoring |
| Examity | Examity | Enterprise deployments |

See `docs/13-lockdown-browsers.md` for a detailed analysis of how each tool detects VMs and what their specific detection vectors are.

## Supplementary VM Detection Tools

Used to validate the VM configuration and understand what a lockdown browser *could* detect:

| Tool | Source |
|---|---|
| Pafish | https://github.com/a0rtega/pafish |
| Al-Khaser | https://github.com/LordNoteworthy/al-khaser |
| VMAware | https://github.com/kernelwernel/VMAware |
| CPU-Z | https://www.cpuid.com/softwares/cpu-z.html |
| HWiNFO64 | https://www.hwinfo.com/ |

## Academic References

**Proctoring Software Security:**
- Burgess, M., & Bergen, N. (2020). "Online Exam Proctoring: An Analysis of Security Measures." *Journal of Academic Ethics.*
- Harmon, O., & Lambrinos, J. (2008). "Are Online Exams an Invitation to Cheat?" *Journal of Economic Education.*
- Cluskey, G. R., Ehlen, C. R., & Raiborn, M. H. (2011). "Thwarting Online Exam Cheating Without Proctor Supervision." *Journal of Academic and Business Ethics.*
- Sietses, L. (2016). "White Paper: Internet-Based Proctoring." SURFnet.

**VM Detection Fundamentals:**
- Raffetseder, Kruegel, Kirda (2007). "Detecting System Emulators." *ISC 2007.*
- Garfinkel, Adams, Warfield, Franklin (2007). "Compatibility is Not Transparency: VMM Detection Myths and Realities." *HotOS XI.*

## Ethical Statement

All testing is performed on VMs and software under the researcher's own control. No exam systems, university networks, or third-party proctoring sessions are targeted. The purpose is evaluation of vendor security claims, consistent with standard security research practice (responsible disclosure applies if significant vulnerabilities are found).

## License

Academic use only. All scripts and configurations are provided for educational and research purposes.
