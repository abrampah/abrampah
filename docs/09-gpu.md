# GPU Detection and Evasion

## A — Detection Vector

The GPU vendor and model are exposed through multiple channels:

**WMI:**
```powershell
Get-WmiObject Win32_VideoController | Select Name, DriverVersion, VideoProcessor
# "Red Hat VirtIO GPU" or "VMware SVGA 3D" → VM detected
```

**DirectX DXGI API:**
```c
IDXGIFactory *factory;
IDXGIAdapter *adapter;
DXGI_ADAPTER_DESC desc;
CreateDXGIFactory(&IID_IDXGIFactory, (void **)&factory);
factory->EnumAdapters(0, &adapter);
adapter->GetDesc(&desc);
// desc.Description = L"Red Hat VirtIO GPU" → VM detected
// Or "llvmpipe (LLVM ...)" for software rendering
```

**D3D device creation failure:**
Some malware attempts to create a Direct3D device and checks if hardware acceleration is available. VMs without GPU passthrough may fail D3D11 hardware device creation, falling back to WARP (software renderer) — a strong VM indicator.

## B — Why It Reveals a VM

QEMU's display options:
- `virtio-vga` / `virtio-gpu` — reports "Red Hat VirtIO GPU" or "Red Hat QXL GPU"
- `qxl-vga` — used with SPICE; reports "Red Hat, Inc. QXL paravirtual video card"
- `vmware-svga` — emulates VMware SVGA 3D; reports "VMware SVGA 3D"
- `-vga std` (default) — Bochs VGA; reports "Standard VGA Compatible Adapter" or "Bochs/QEMU" in BIOS

None of these match a real Intel UHD 630, which is the integrated GPU in the i7-10700 (claimed in our SMBIOS).

**Software rendering fallback:**
Without GPU hardware or a passthrough, 3D acceleration uses WARP (Windows Advanced Rasterization Platform) or llvmpipe. WMI reports these accurately.

## C — Evasion Options

**Option 1 — VirtIO-VGA with registry patching (easiest, imperfect):**
```bash
-device virtio-vga
```
Then `scripts/registry-patch.ps1` patches the display driver description from "Red Hat VirtIO GPU" to "Intel(R) UHD Graphics 630". This fixes WMI string queries but does NOT fix the DXGI adapter description — DXGI reads from the driver itself, not the registry string.

**Option 2 — GPU passthrough with VFIO (best, requires dedicated GPU):**
GPU passthrough assigns a physical GPU directly to the VM. The guest sees the real GPU with its real PCI IDs, real driver, and real DXGI adapter description.

Requirements:
- Host CPU with IOMMU (Intel VT-d or AMD-Vi)
- Dedicated GPU not used by host (iGPU for host display, dGPU for VM)
- VFIO kernel modules

```bash
# Bind GPU to VFIO on host
echo "0000:01:00.0" > /sys/bus/pci/drivers/vfio-pci/bind

# Pass through to QEMU
-device vfio-pci,host=01:00.0
```

With passthrough, the VM sees the full GPU identity — DXGI, WMI, and hardware IDs all match a real GPU.

**Option 3 — VirtIO-VGA with EDID injection:**
QEMU 5.2+ supports EDID injection for `virtio-vga`:
```bash
-device virtio-vga,edid=on,xres=3840,yres=2160
```
This makes the display claim to be a 4K monitor, reducing suspicion from resolution checks. Combined with the Dell EDID binary from `vm/edid/`, this addresses EDID-based detection. The adapter description remains VirtIO.

**Current implementation:** Option 1 (registry patch) for compatibility; Option 2 documented as "advanced/optional."

## D — Defensive Implications

GPU detection is the detection vector that is **hardest to defeat without hardware**:
- Registry string patches are superficial — DXGI bypasses them
- VirtIO always exposes Red Hat PCI vendor ID in PCI config space
- WARP software rendering has distinct performance characteristics

For a research/academic project without dedicated passthrough GPU hardware, the GPU remains a detectable artifact. This is an honest finding — document it as such.

**For defenders (sandbox designers):**
GPU passthrough in sandboxes is rarely implemented because:
- It requires dedicated GPU hardware per sandbox instance (costly at scale)
- GPU drivers are complex and can be exploited
- Many malware samples don't use GPU-based detection (it's a newer technique)

Emerging approaches use containerized GPU passthrough (SR-IOV) that allows partial GPU sharing, but production deployment is limited. This area represents active research.
