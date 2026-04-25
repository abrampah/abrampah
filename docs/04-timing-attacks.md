# Timing Attack Detection and Evasion

## A — Detection Vector

Timing attacks measure the execution time of specific CPU instructions to detect VM exit overhead. The key check: execute `CPUID` (which causes a VM exit in a hypervisor) and measure the cycle count before and after using `RDTSC`.

**Pafish implementation (simplified):**
```c
uint64_t before, after, delta;

// Measure RDTSC overhead without VM exit
__asm__ volatile("rdtsc" : "=A"(before));
__asm__ volatile("rdtsc" : "=A"(after));
uint64_t baseline = after - before;

// Measure RDTSC with CPUID (forces VM exit)
__asm__ volatile("rdtsc" : "=A"(before));
__asm__ volatile("cpuid" : : "a"(0) : "ebx", "ecx", "edx");
__asm__ volatile("rdtsc" : "=A"(after));
delta = after - before - baseline;

// On real hardware: delta < ~200 cycles
// Under KVM: delta > ~1000 cycles (VM exit latency)
if (delta > THRESHOLD) {
    // Detected as VM
}
```

Al-Khaser uses a similar approach with `RDTSCP` (which includes a processor ID read, making it more precise) and samples multiple iterations.

## B — Why It Reveals a VM

When a guest executes `CPUID`, KVM must handle it in the hypervisor (VMX/SVM VM exit). This involves:
1. Guest CPU saves state (VMCS/VMCB write)
2. Context switch to host kernel
3. KVM processes the CPUID request
4. Context switch back to guest
5. Guest CPU restores state

This round-trip takes hundreds to thousands of nanoseconds — far more than the sub-nanosecond execution of CPUID on real hardware, where it executes directly in the CPU pipeline.

Even with `kvm=off`, KVM must still handle CPUID to return the spoofed values. The VM exit is hidden (no hypervisor bit), but the timing artifact remains.

## C — Evasion Implementation

**`+invtsc` — Invariant TSC:**
```bash
-cpu host,...,+invtsc,+rdtscp
```

`invtsc` (invariant TSC) ensures the TSC ticks at a constant rate regardless of CPU power state changes (C-states, frequency scaling). Without it, TSC rate variations add noise that increases the variance of timing measurements and can make VM detection thresholds unreliable. With it, the baseline is more stable, reducing (but not eliminating) the RDTSC delta.

**Disable HPET and KVM paravirt clock:**
```bash
-no-hpet
```
```xml
<timer name="hpet"     present="no"/>
<timer name="kvmclock" present="no"/>
<timer name="hypervclock" present="no"/>
```

KVM's paravirt clock (`kvmclock`) is a direct VM indicator — it's a KVM-specific feature that doesn't exist on real hardware. Disabling it removes this signal.

HPET (High Precision Event Timer) under KVM has higher latency than on real hardware. Disabling HPET forces Windows to use the TSC or APIC timer, which behaves more realistically.

**RTC configuration:**
```bash
-rtc base=localtime,clock=host,driftfix=slew
```

Synchronizes the VM's RTC to the host wall clock with drift correction, preventing time-skew-based detection (comparing wall clock time to TSC-based elapsed time).

## D — Defensive Implications

Timing attacks represent the most fundamental and hardest-to-defeat VM detection vector:

**Why it cannot be fully eliminated in software:**
- VM exits are inherent to the VMX/SVM architecture. Every instruction that requires hypervisor intervention causes measurable latency.
- Even with `invtsc`, the RDTSC-over-CPUID delta is typically 3-10x larger under KVM than on bare metal.
- The distribution of timing values (not just the mean) is statistically distinguishable between VM and bare metal.

**Measurement-based detection is resilient:**
A sufficiently sophisticated detector can:
1. Take thousands of timing samples
2. Fit a distribution to the results
3. Compare the variance and tail behavior to known bare-metal distributions
4. Detect VM even when single-sample thresholds are defeated by `+invtsc`

**Practical mitigations for defenders:**
- **Bare-metal sandboxes:** VMRay and some enterprise sandboxes avoid VMs entirely, running malware on dedicated physical machines with hardware reimaging. Timing attacks become irrelevant.
- **Hardware-assisted isolation:** Intel TDX and AMD SEV-SNP provide confidential VMs where some instructions are handled without traditional VM exits, reducing measurable overhead.
- **Adaptive thresholds:** Rather than fixed cycle thresholds, use machine-specific calibration. This is harder for malware authors to target since the threshold varies per sandbox instance.

**Academic reference:** Raffetseder et al. (ISC 2007) provide a formal analysis of timing-based VM detection and the inherent detectability of software-only virtualization. They conclude that defeating timing attacks requires hardware support — a finding that remains valid.
