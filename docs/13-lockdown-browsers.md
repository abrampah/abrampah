# Lockdown Browser VM Detection Analysis

## Overview

This document analyzes how major academic proctoring applications detect virtual machines, what specific checks they implement, and how the VM hardening techniques in this project address each one.

The information here is derived from:
- Reverse engineering and behavioral analysis (publicly documented by security researchers)
- Academic papers on proctoring software security
- Vendor documentation and marketing materials
- Student/researcher reports in the gray literature

---

## Respondus LockDown Browser (RLDB)

### What It Is
The most widely deployed lockdown browser in US higher education. A modified Chromium build that replaces the standard browser. Locks the system: disables task switching, right-click, keyboard shortcuts, screen capture, and attempts to block access to other applications.

### VM Detection Approach

**Checks documented by reverse engineering and user reports:**

| Check | Method | Certainty |
|---|---|---|
| Hypervisor CPUID bit | `IsProcessorFeaturePresent(PF_VIRT_FIRMWARE_ENABLED)` or direct CPUID | High |
| WMI hardware strings | `Win32_ComputerSystem.Manufacturer` for QEMU/VirtualBox/VMware | High |
| Running VM processes | Process snapshot check for vmtoolsd.exe, VBoxService.exe | High |
| VM-related registry keys | HKLM\SOFTWARE\Oracle, VMware, etc. | High |
| Screen resolution | GetSystemMetrics check for minimum resolution | Medium |
| Secondary monitors | `EnumDisplayMonitors` — blocks multi-monitor setups | High |
| Screen recording software | Process check for OBS, Camtasia, ShareX, etc. | High |
| Network shares (VBox shared folders) | Named pipe enumeration | Medium |

**What RLDB does NOT currently appear to check (based on behavioral analysis):**
- SMBIOS type 1 manufacturer/model in detail (only surface WMI strings)
- Disk drive SMART data
- Timing attacks (RDTSC delta)
- PCI device hardware IDs
- MAC address OUI prefix
- ACPI table contents

### How Our Hardened VM Addresses RLDB Checks

| RLDB Check | Our Countermeasure | Expected Result |
|---|---|---|
| CPUID hypervisor bit | `hypervisor=off`, `kvm=off` in `-cpu` flags | PASS — bit cleared |
| WMI Manufacturer/Model | SMBIOS type=1: Dell Inc. / OptiPlex 7090 | PASS — string check fails to detect |
| VM process names | No VMware/VBox tools installed; VirtIO is kernel-only | PASS — no matching processes |
| VM registry keys | `registry-patch.ps1` removes all vendor keys | PASS — keys absent |
| Screen resolution | VM configured at 1920×1080 minimum | PASS — resolution acceptable |
| Secondary monitors | Single display configured | PASS — only 1 monitor |
| Screen recording software | None installed in VM | PASS |
| Named pipes (shared folders) | No VirtIO-fs or VBox shared folders configured | PASS |

### Residual Risk with RLDB

RLDB could theoretically tighten its detection to catch our configuration via:
- PCI hardware ID enumeration (VirtIO GPU if used: VEN_1AF4)
- Driver binary hash verification (viostor.sys, NetKVM.sys present in System32)
- RDTSC timing check (not currently implemented but feasible)

---

## Honorlock

### What It Is
Integrates with Canvas LMS. Runs as a Chrome extension plus a native companion application. Includes AI-based behavior monitoring (eye tracking, secondary device detection via audio).

### VM Detection Approach

Honorlock's native companion runs on the host OS and performs checks:

| Check | Method |
|---|---|
| Hypervisor CPUID | Standard Windows API / CPUID instruction |
| WMI computer system | `Win32_ComputerSystem` manufacturer check |
| VM service enumeration | Registry/WMI service listing |
| Screen recording detection | Process monitoring for known screen capture apps |
| Secondary screen | Multi-monitor enumeration |
| Audio monitoring | Microphone access for background noise analysis |
| Browser integrity | Chrome extension monitors DOM and tab activity |

**Key difference from RLDB:** Honorlock's Chrome extension runs inside the browser, limiting its access to OS-level checks. The native companion process has higher privilege.

### How Our Hardened VM Addresses Honorlock

Same OS-level countermeasures apply (CPUID, SMBIOS, registry, processes). The Chrome extension cannot perform CPUID or registry checks — those are OS-level operations not accessible from JavaScript. The native companion's checks are equivalent to RLDB's.

**Additional consideration for Honorlock:**
Honorlock uses AI webcam monitoring. Running the VM inside a physical laptop means the webcam captures the student's face normally — Honorlock's AI sees a real person, not a VM artifact. The VM detection would need to succeed for Honorlock to flag the session.

---

## Proctorio

### What It Is
Purely Chrome extension-based (no native application). This is architecturally significant: a Chrome extension cannot make raw Win32 API calls, cannot read the registry directly, and cannot execute CPUID.

### VM Detection Approach

Proctorio is significantly more limited in VM detection because:
- JavaScript running in a Chrome extension has no access to CPUID
- Registry access is not available from browser context
- WMI queries require COM/PowerShell — not available in extension context

What Proctorio *can* check from a Chrome extension:
- `navigator.hardwareConcurrency` — CPU core count (unusual if very low)
- `navigator.deviceMemory` — reported RAM (capped at 8 in Chrome, not useful)
- WebGL renderer string — can expose llvmpipe, SVGA, or VirtIO GPU strings
- `screen.width` / `screen.height` — resolution check
- `window.outerWidth` / `window.outerHeight` — window vs screen size ratio

**WebGL renderer is the most significant Proctorio check:**
```javascript
const canvas = document.createElement('canvas');
const gl = canvas.getContext('webgl');
const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
const renderer = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
// "ANGLE (Intel, Intel(R) UHD Graphics 630, OpenGL 4.6)"  → looks real
// "ANGLE (VMware, SVGA3D; build: RELEASE;)"               → VM detected
// "llvmpipe (LLVM 15.0.7, 256 bits)"                     → software rendering, VM detected
```

### How Our Hardened VM Addresses Proctorio

| Proctorio Check | Our Countermeasure | Expected Result |
|---|---|---|
| WebGL renderer string | virtio-vga with registry patch to Intel UHD 630; or GPU passthrough | PARTIAL — registry patch fixes WMI; WebGL reads from driver, not registry |
| Screen resolution | VM at 1920×1080 | PASS |
| Hardware concurrency | 4 vCPUs configured | PASS |

**WebGL is the significant remaining gap for Proctorio:**
The WebGL renderer string is read from the GPU driver itself, not the registry. Our registry patch (`registry-patch.ps1` Section 4) fixes `Win32_VideoController.Name` but not the WebGL renderer string.

**Options to fix WebGL renderer:**
1. **GPU passthrough** (best): A real GPU passed through shows its real WebGL renderer
2. **Mesa/ANGLE spoofing**: On Linux host with VirtIO-GL, the Mesa driver can be compiled with a custom renderer string
3. **Chrome flag**: `--disable-gpu` forces WARP software rendering but is suspicious ("SwiftShader" appears)
4. **virtio-vga with gl=on**: Uses host GPU via VirtIO-GPU protocol; the renderer string may reflect the host GPU, which could be legitimate

For a thorough evaluation, test specifically what WebGL renderer string appears in the hardened VM configuration before concluding Proctorio is bypassed.

---

## ProctorU / Meazure Learning

### What It Is
Hybrid live + automated proctoring. A human proctor watches via webcam, supplemented by automated software checks. The desktop sharing component is a native application.

### VM Detection Approach

ProctorU's native application performs standard OS-level checks:
- CPUID hypervisor bit
- WMI system enumeration
- Process/service inspection
- Screen sharing detection

The human proctor element adds a dimension that software analysis cannot: a proctor watching a screen share might notice unusual behavior (e.g., VM window decorations visible, unusual screen layout, lag consistent with nested display).

**Human proctoring and VM detection:**
- If the lockdown browser runs inside a VM with a GUI display, the proctor sees whatever is on the VM's virtual screen — which looks like a normal Windows desktop
- If the student uses a borderless full-screen VM window, there is no visual indicator that a VM is in use
- Proctor detection of VM usage requires the student to make a mistake (e.g., accidentally revealing the VM window border, host taskbar visible in a recording)

---

## Detection Matrix: All Tools

| Check Vector | RLDB | Honorlock | Proctorio | ProctorU | Our Countermeasure |
|---|---|---|---|---|---|
| CPUID hypervisor bit | Yes | Yes | No (JS) | Yes | `hypervisor=off`, `kvm=off` |
| WMI manufacturer/model | Yes | Yes | No (JS) | Yes | SMBIOS override |
| VM registry keys | Yes | Yes | No (JS) | Yes | `registry-patch.ps1` |
| VM process names | Yes | Yes | No (JS) | Yes | No guest agents |
| Screen resolution | Yes | Yes | Yes | Yes | 1920×1080+ |
| WebGL renderer | Unlikely | Unlikely | **Yes** | Unlikely | Partial (see above) |
| Multi-monitor | Yes | Yes | Yes (JS) | Yes | Single display |
| Screen recording | Yes | Yes | Yes (JS) | Yes | None installed |
| MAC OUI | No | No | No | No | `mac-spoof.sh` (belt-and-suspenders) |
| Disk model | No | No | No | No | NVMe Samsung string |
| RDTSC timing | No | No | No | No | `+invtsc` (belt-and-suspenders) |

---

## Recommendations for the Research Write-Up

### Hypothesis
A QEMU/KVM VM configured with the techniques in this repository will pass VM detection checks in Respondus LockDown Browser and Honorlock. Proctorio has partial residual detection via WebGL renderer string.

### Experimental Design
1. Install each proctoring tool in the hardened VM
2. Attempt to launch a test/demo exam session
3. Note whether the software blocks launch, flags the session, or proceeds normally
4. Document the exact error message (if any) — this reveals what check triggered
5. For Proctorio: capture the WebGL renderer string and document whether it appears legitimate

### Expected Contribution
A quantitative table showing which proctoring tools detect which VM configurations, and which configurations defeat detection. This directly answers the research question and has practical value for universities evaluating proctoring software security.

### Vendor Notification
Before final submission, consider notifying vendors of specific technical findings:
- Respondus: security@respondus.com
- Honorlock: security@honorlock.com
- Proctorio: security@proctorio.com

This demonstrates responsible research practice and may result in vendor acknowledgment in the paper.
