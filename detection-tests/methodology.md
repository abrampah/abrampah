# Detection Test Methodology

## Research Objective

Determine whether academic proctoring software (Respondus LockDown Browser, Honorlock, Proctorio, ProctorU) can detect that an exam session is running inside a hardened QEMU/KVM virtual machine.

## Test Environment

| Component | Value |
|---|---|
| Host OS | Ubuntu 24.04 LTS (bare-metal KVM required) |
| Hypervisor | QEMU 8.2.x / KVM |
| Guest OS | Windows 11 Pro 23H2 (64-bit) |
| QEMU machine type | q35 |
| VM RAM | 8 GB |
| VM vCPUs | 4 (2 cores × 2 threads) |
| Claimed hardware identity | Dell OptiPlex 7090, Intel i7-10700 |

## Phase 1 — Baseline VM (no evasion)

**Purpose:** Establish how proctoring tools behave against a stock QEMU VM with no hardening. Document which checks trigger, and what error messages appear.

**Setup:**
1. Launch QEMU with only basic parameters (no `-cpu` tricks, no `-smbios`, default drivers)
2. Install Windows 11 with default VirtIO drivers
3. Take a snapshot named `baseline`

**Procedure for each proctoring tool:**
1. Install the proctoring software per vendor instructions
2. Navigate to a demo exam or the software's self-check page
3. Note the exact outcome:
   - Does the software launch?
   - Does it display a "VM detected" or "unsupported environment" error?
   - What is the exact error message? (Screenshot required)
   - Does it launch with a warning but proceed?
4. If the software launches, attempt to open a second application or browser tab to test isolation
5. Document all observations in `results-baseline.md`

**Error message logging is critical** — the exact text often reveals which check triggered (e.g., "Virtual machine detected" vs. "Unsupported graphics configuration" vs. "Please disable screen sharing software").

## Phase 2 — Incremental Hardening

Apply techniques in order, retesting proctoring software after each step. This identifies the minimum configuration needed to bypass each tool's detection.

| Step | Technique | Files Modified |
|---|---|---|
| 1 | CPUID: `hypervisor=off`, `kvm=off` | `vm/launch.sh`, `vm/windows-stealth.xml` |
| 2 | SMBIOS: Dell OptiPlex 7090 identity | Same — add all `-smbios type=N` flags |
| 3 | Registry cleanup | Run `scripts/registry-patch.ps1` in guest |
| 4 | Driver INF rename | Run `scripts/driver-rename.py` before reinstalling drivers |
| 5 | Timing: `+invtsc`, disable HPET/kvmclock | `vm/launch.sh` clock section |
| 6 | Storage model string | NVMe Samsung 970 model/serial |
| 7 | Network MAC | `scripts/mac-spoof.sh` |
| 8 | ACPI fake battery | `vm/acpi/build-acpi.sh` + `-acpitable` flag |
| 9 | OVMF firmware | Replace SeaBIOS with OVMF |

**For each step:**
1. Apply only the new technique (revert to baseline, then apply steps 1 through N)
2. Reboot VM
3. Retest proctoring software
4. Record whether behavior changed (new error, same error, software now launches)
5. Screenshot new state
6. Update `results-matrix.csv`

## Phase 3 — Fully Hardened

Apply all techniques simultaneously using the complete `vm/launch.sh`:
1. Run `scripts/driver-rename.py` on virtio-win drivers before Windows install
2. After install, run `scripts/registry-patch.ps1`
3. Follow `scripts/post-install-checklist.md`
4. Test all proctoring tools

Document in `results-hardened.md`.

## Phase 4 — WebGL Renderer Audit (Proctorio specific)

Proctorio reads the WebGL renderer string from JavaScript. This is separate from WMI/CPUID checks.

**Test procedure:**
1. In the VM, open Chrome (not inside Proctorio)
2. Open DevTools Console (F12)
3. Run:
   ```javascript
   const canvas = document.createElement('canvas');
   const gl = canvas.getContext('webgl');
   const ext = gl.getExtension('WEBGL_debug_renderer_info');
   console.log('Vendor:', gl.getParameter(ext.UNMASKED_VENDOR_WEBGL));
   console.log('Renderer:', gl.getParameter(ext.UNMASKED_RENDERER_WEBGL));
   ```
4. Record the exact strings

**Expected results by display configuration:**

| QEMU Display Option | Expected WebGL Renderer | Proctorio Result |
|---|---|---|
| `-device virtio-vga` (no GL) | "ANGLE (Red Hat, VirtIO ..." or software | DETECTED |
| `-device virtio-vga,edid=on` | Same as above | DETECTED |
| `-device virtio-vga-gl -display gtk,gl=on` | Host GPU renderer via VirtIO-GPU | Likely NOT DETECTED |
| GPU passthrough (VFIO) | Real GPU string (e.g., NVIDIA GeForce) | NOT DETECTED |
| `-device qxl-vga` | "ANGLE (VMware, SVGA3D...)" | DETECTED |

Document the WebGL string in `results-hardened.md` under the Proctorio section.

## Phase 5 — Behavioral Observation (all tools)

After the proctoring software launches successfully (not blocked by VM detection):

1. **Screen share capture:** Start the exam session. In a separate window on the host (outside VM), observe what the proctor would see. The VM desktop should appear as a normal Windows environment.

2. **Application blocking test:** While LockDown Browser is running inside the VM:
   - Attempt to open Notepad inside the VM — should be blocked by LDB
   - Switch to host OS — LDB cannot see or control the host OS
   - Open a browser on the host — accessible, invisible to LDB

3. **Document the isolation boundary** — what LDB controls (inside VM) vs. what it cannot see (host OS)

This is the core research finding: even if LDB runs normally, its isolation is bounded by the VM boundary.

## Recording Results

### results-matrix.csv schema
```
tool,version,check_name,baseline_result,step1_cpuid,step2_smbios,step3_registry,step4_drivers,step5_timing,step6_storage,step7_network,step8_acpi,hardened_result,notes
```

### Screenshot convention
```
screenshots/
  baseline/
    rldb-baseline-error.png         — error message from stock VM
    honorlock-baseline-error.png
    proctorio-baseline-webgl.png    — WebGL renderer string from console
  step-01-cpuid/
    rldb-after-cpuid-hide.png
  hardened-final/
    rldb-launched.png               — LDB running successfully in hardened VM
    honorlock-launched.png
    proctorio-webgl-hardened.png    — WebGL renderer string in hardened VM
    host-browser-open.png           — host OS browser accessible while LDB runs in VM
```

## Success Criteria

The research hypothesis is **confirmed** if:
1. At least one proctoring tool launches without VM detection errors in the hardened VM
2. While that tool runs, the host OS remains accessible
3. The tool's exam isolation controls apply only inside the VM

The research hypothesis is **partially confirmed** if:
- Some tools are bypassed but others detect the VM
- The WebGL check in Proctorio remains an unresolved detection vector

**Either outcome is scientifically valid** — documenting that some tools detect the VM and others do not, with the specific differentiating checks identified, is a complete research finding.

## Supplementary Tool Testing

In addition to the proctoring software, run these tools to validate the VM's general posture:

| Tool | Purpose |
|---|---|
| Pafish | Validates CPUID, timing, registry checks pass |
| VMAware | Confidence score as a quantitative VM-likeness metric |
| HWiNFO64 | Visually confirms SMBIOS identity (Dell OptiPlex 7090) |
| CPU-Z | Cross-checks CPUID and SMBIOS |
| Chrome DevTools | WebGL renderer string audit |

These tools don't test proctoring software directly but confirm the VM hardening is working before the primary test.
