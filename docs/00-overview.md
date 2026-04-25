# Project Overview: Windows VM Indistinguishability Research

## Research Question

Can a QEMU/KVM-based Windows virtual machine be configured to defeat common VM detection techniques used by malware? If so, which techniques are most effective, which remain detectable, and what does this reveal about the fundamental limits of sandbox-based malware analysis?

## Motivation

Dynamic malware analysis — running a suspicious binary in a controlled environment and observing its behavior — is a foundational technique in security operations. Sandboxes like Cuckoo, Any.run, and commercial AV emulation environments all rely on VMs to safely execute malware.

Malware authors are well aware of this. A significant portion of modern malware includes VM detection code: before executing its primary payload, the malware checks whether it is running in a VM, and if so, either exits silently or behaves benignly. This evasion defeats sandbox analysis, allowing the malware to reach real victims without being analyzed.

Understanding exactly *how* malware detects VMs — and *how far* that detection can be defeated — is essential for:
- Building more robust analysis sandboxes
- Understanding the arms race between detection and evasion
- Evaluating the trustworthiness of sandbox analysis results

## Approach

This project configures a QEMU/KVM Windows 11 VM to minimize detectable VM artifacts. Each technique is documented with its detection vector, implementation, and defensive implications. The effectiveness is measured quantitatively using Pafish, Al-Khaser, VMAware, and custom scripts.

## Threat Model

The adversary is malware running inside the VM that attempts to determine whether it is in a virtualized environment. The adversary can:
- Execute arbitrary CPU instructions (CPUID, RDTSC)
- Query the Windows registry
- Enumerate running processes and services
- Issue WMI queries
- Inspect hardware device strings

The adversary cannot directly observe the host OS or hypervisor.

## Detection Technique Categories

| Category | Example Checks |
|---|---|
| CPUID | Hypervisor present bit, KVM vendor string, leaf count |
| Timing | RDTSC delta across VM exits, GetTickCount correlation |
| SMBIOS/DMI | Manufacturer, model, board strings |
| ACPI | DSDT OEM ID, battery presence, timer tables |
| Registry | VM vendor software keys, service names |
| Drivers | NIC/GPU/storage driver vendor strings |
| Network | MAC OUI prefix |
| Storage | Disk model string |
| Process/Service | vmtoolsd.exe, VBoxService.exe |
| Display | Screen resolution, EDID presence |

## Key Findings (Preview)

See `results-hardened.md` for quantitative results. High-level:
- CPUID and SMBIOS spoofing eliminates the majority of detections
- Timing attacks are the hardest to fully defeat in software
- Some PCI device topology artifacts are fundamentally un-spoofable without hardware passthrough
- The techniques documented here are well-known in the security community and are already defeated by advanced sandboxes using bare-metal analysis

## Ethical and Legal Context

All techniques documented here are performed on a VM under the researcher's control. No third-party systems are affected. The knowledge is openly published in academic papers, security conferences (Black Hat, DEF CON, academic venues), and open-source tool repositories. Understanding these techniques is standard curriculum in malware analysis and reverse engineering.
