# CPUID-Based VM Detection and Evasion

## A — Detection Vector

The `CPUID` instruction returns processor identification and feature information. Virtualization hypervisors use specific CPUID leaves to communicate capabilities to the guest OS.

**Key leaves checked by detection tools:**

**Leaf 1 (Feature Information), ECX bit 31 — Hypervisor Present Bit:**
```c
// C example of the detection check
uint32_t ecx;
__asm__ volatile("cpuid" : "=c"(ecx) : "a"(1) : "ebx", "edx");
if (ecx & (1 << 31)) {
    // Running under a hypervisor
}
```

**Leaf 0x40000000 — Hypervisor Vendor String:**
When the hypervisor present bit is set, software can read the hypervisor's vendor string:
```c
char vendor[13] = {0};
uint32_t regs[3];
__asm__ volatile("cpuid" : "=b"(regs[0]), "=c"(regs[1]), "=d"(regs[2]) : "a"(0x40000000));
memcpy(vendor, regs, 12);
// KVM returns: "KVMKVMKVM\0\0\0"
// VMware: "VMwareVMware"
// Hyper-V: "Microsoft Hv"
```

**Leaf 0x40000001 — Hyper-V Interface Signature:**
KVM with Hyper-V emulation sets this leaf. Al-Khaser checks for the value `0x31237648` ("Hv#1").

## B — Why It Reveals a VM

On real hardware, CPUID leaf 1 ECX bit 31 is always 0 — no hypervisor present. The hypervisor leaves (0x40000000+) are undefined and return 0 on real hardware.

KVM sets bit 31 by default and exposes the `KVMKVMKVM` vendor leaf because:
- It allows the guest to use KVM paravirt optimizations (clock, balloon, etc.)
- Some guest drivers rely on detecting KVM to load optimized codepaths

This is useful for performance but fatal for concealment.

## C — Evasion Implementation

**QEMU CLI:**
```bash
-cpu host,hypervisor=off,kvm=off,hv-vendor-id=AuthenticAMD
```

- `hypervisor=off` — clears CPUID leaf 1 ECX bit 31
- `kvm=off` — suppresses KVM's own CPUID leaves (0x40000000-0x40000002)
- `hv-vendor-id=AuthenticAMD` — sets Hyper-V leaf 0x40000000 vendor to `AuthenticAMD` instead of `Microsoft Hv` (if Hyper-V enlightenments are active)

**libvirt XML (in `vm/windows-stealth.xml`):**
```xml
<cpu mode="host-passthrough" check="none">
  <feature policy="disable" name="hypervisor"/>
</cpu>
<features>
  <kvm>
    <hidden state="on"/>
  </kvm>
  <hyperv mode="passthrough">
    <vendor_id state="on" value="AuthenticAMD"/>
  </hyperv>
  <vmport state="off"/>
</features>
```

`<vmport state="off"/>` disables the VMware backdoor I/O port (0x5658 / "VMXH"), which VMware uses for guest-host communication. QEMU emulates this port by default; disabling it removes another detection vector.

## D — Defensive Implications

Defenders (sandbox authors) cannot easily counter this evasion because:
- Once the hypervisor bit is cleared, there is no way for a guest instruction to distinguish KVM with `kvm=off` from real hardware via CPUID alone
- The `AuthenticAMD`/`GenuineIntel` vendor string is what real hardware returns

More robust defenses include:
- **Bare-metal analysis:** Some enterprise sandboxes (e.g., VMRay) run malware directly on physical hardware, avoiding the hypervisor bit entirely
- **Leaf count analysis:** Real hardware typically returns 0 for undefined leaves; hypervisors sometimes expose different values in reserved leaves
- **CPUID leaf 4 (cache topology):** The exact topology returned must match a real CPU model; spoofed values may be inconsistent with claimed CPU identity

The CPUID arms race illustrates a fundamental asymmetry: the defender must add more and more obscure checks, while the attacker needs only to match the behavior of any real CPU.
