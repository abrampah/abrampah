# Project Overview: Evaluating VM Detection in Academic Proctoring Software

## Research Question

Do commercial lockdown browser and academic proctoring applications reliably detect that an exam session is running inside a virtual machine? If not, what does this mean for the security guarantees these products claim to provide?

## Background

Online exam proctoring software is now standard infrastructure at US universities. Products like **Respondus LockDown Browser**, **Honorlock**, **Proctorio**, and **ProctorU** are used across millions of exam sessions. Their core security model rests on the following assumptions:

1. The student is using a real, unmodified physical machine
2. The proctoring software can detect and block unauthorized applications
3. Virtual machines can be detected and flagged as a policy violation

Assumption 3 is the focus of this research. If a VM can be configured such that proctoring software cannot distinguish it from physical hardware, then:
- A student could run the lockdown browser inside a VM
- The host OS (outside the VM) remains fully accessible
- The proctoring software's access controls are bypassed

This is not a novel observation — security researchers and students have noted this possibility for years. What this project provides is a **systematic, documented, and measurable evaluation** of how effective current VM detection is in these products.

## Why This Research Matters

**For universities and IT administrators:**
Understanding the actual security posture of proctoring tools is necessary for informed policy decisions. Administrators who believe VM detection is reliable may accept higher-risk exam configurations. Accurate evaluation enables better risk management.

**For proctoring software vendors:**
Systematic documentation of detection gaps enables vendors to improve their products. This research follows the responsible disclosure model — findings can be shared with vendors before public release.

**For computer science education:**
This is precisely the type of applied security research that MS Networks and Cybersecurity students should conduct: identifying a real-world security claim, designing a test methodology, measuring the result, and documenting the implications.

## Scope

**In scope:**
- QEMU/KVM VM configuration to minimize detectable VM artifacts
- Behavioral testing of lockdown browser software against the hardened VM
- Documentation of which VM artifacts are detected vs. missed
- Analysis of what the results mean for proctoring security

**Out of scope:**
- Attacking or disrupting any live exam session
- Bypassing authentication or server-side integrity checks
- Network-level or web application attacks against proctoring platforms
- Any testing against a university system without explicit authorization

## Threat Model (from the vendor's perspective)

The adversary is a student who attempts to take an exam with the lockdown browser running inside a VM, while the host OS provides access to notes, browsers, communication tools, or answer lookup services.

The lockdown browser is the "defender." It attempts to detect:
1. That it is running in a virtualized environment
2. That screen recording or streaming software is active
3. That a secondary display is connected
4. That browser isolation has been compromised

This project focuses on detection vector #1 (VM detection) because it is the one directly addressable through VM configuration.

## Detection Technique Categories (applied to proctoring context)

| Category | Lockdown Browser Relevance |
|---|---|
| CPUID hypervisor bit | High — direct, low-cost check in any Windows process |
| SMBIOS/DMI strings | High — WMI queries are trivial to implement |
| Registry artifacts | High — VirtIO/VMware keys trivially enumerable |
| Running processes | High — VM guest agents are process-visible |
| Screen resolution | Medium — very small resolutions flag headless VMs |
| Timing attacks | Low — proctoring software unlikely to implement; too false-positive-prone |
| Driver PCI IDs | Low — requires deeper Windows driver API access |

See `docs/13-lockdown-browsers.md` for the lockdown-browser-specific analysis.

## Methodology Overview

1. Configure a QEMU/KVM Windows VM with all anti-detection techniques (documented in `docs/01-12-*.md`)
2. Install target proctoring software in the hardened VM
3. Attempt to launch an exam session or trigger the lockdown browser's VM check
4. Observe whether the software detects virtualization or proceeds normally
5. Document findings in `detection-tests/`

## Key Prior Work

- Swauger, S. (2020). "Our Bodies Encoded: Algorithmic Test Proctoring in Higher Education." *Hybrid Pedagogy.*
- Burgess & Bergen (2020). "Online Exam Proctoring." Identify VM detection as an unverified assumption.
- Multiple student/researcher blog posts documenting successful LDB bypass via VMs (gray literature, not peer-reviewed, but demonstrate the practical feasibility).
- SURFFNET White Paper (Sietses, 2016) — systematic evaluation of Dutch university proctoring products, notes VM detection weakness.

## Responsible Disclosure Note

If this research identifies specific, exploitable weaknesses in a vendor's VM detection implementation (beyond the general architectural weakness documented here), findings will be disclosed to the vendor with a 90-day remediation window before public release, consistent with standard coordinated disclosure practice.
