# Screen Resolution and EDID Injection

## A — Detection Vector

**Resolution check:**
Some sandbox detectors check for unrealistically small screen resolutions:
```c
int width = GetSystemMetrics(SM_CXSCREEN);
int height = GetSystemMetrics(SM_CYSCREEN);
if (width < 800 || height < 600) {
    // Likely a headless VM or minimal resolution sandbox
}
```
Pafish flags resolutions smaller than 800×600.

**EDID presence:**
More sophisticated checks enumerate connected monitors and check for EDID (Extended Display Identification Data). A VM with no connected physical monitor either returns no EDID or a synthetic one with obvious fake values:
```c
DISPLAYCONFIG_PATH_INFO paths[32];
DISPLAYCONFIG_MODE_INFO modes[32];
UINT32 pathCount = 32, modeCount = 32;
QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths, &modeCount, modes, NULL);
// Check for EDID manufacturer ID and monitor model in adapter name
```

A VM with no monitors (headless) returns no active display paths at all — an unusual state for a "real workstation."

## B — Why It Reveals a VM

VMs without display passthrough have no physical monitor connected. The guest OS either:
- Uses a virtual framebuffer with no EDID (no connected monitor detected)
- Generates a synthetic EDID with generic values ("Generic PnP Monitor")
- Runs at a low default resolution (800×600 or 1024×768) because no monitor reports its supported modes

Physical workstations almost always have at least one monitor connected with a real EDID. The absence of EDID or presence of a "Generic PnP Monitor" is a weak but consistent VM indicator when combined with other signals.

## C — Evasion Implementation

**Resolution configuration:**
Set a realistic resolution in the VM display settings. For Windows 11 with VirtIO display and a GTK window:
- Run `vm/launch.sh` with a GUI display at 1920×1080 minimum
- Or set in the VM: Display Settings → 3840×2160 (4K)

With `virtio-vga` and `edid=on`:
```bash
-device virtio-vga,edid=on,xres=3840,yres=2160
```
QEMU automatically generates an EDID claiming a 3840×2160 display.

**Custom EDID binary:**
`vm/edid/generate-edid.py` generates a Dell U2722D EDID. To use it, the EDID must be injected at the hypervisor level. QEMU 5.2+ with `virtio-vga` supports this via the `edid=on` flag (uses auto-generated EDID based on `xres`/`yres`).

For a custom binary EDID, options include:
- Patching QEMU to read the binary from a file (requires source modification)
- Using `xrandr --newmode` on the host display server before the VM starts
- KMS/DRM direct EDID override on the host (varies by GPU driver)

The Dell U2722D EDID binary (`vm/edid/dell-u2722d.bin`) is provided for environments where custom injection is available.

**VNC/remote display:**
When using VNC for headless access, Windows reports the VNC virtual monitor. This doesn't expose an EDID but the VNC driver string may be detectable. For testing, use a local display (`-display gtk`) rather than VNC.

## D — Defensive Implications

EDID-based detection is currently underutilized by commodity malware because:
- It requires more complex implementation (DDC/CI queries, DISPLAYCONFIG API)
- Most malware focuses on simpler, higher-confidence checks first
- The absence of EDID alone is not a reliable VM indicator (some physical monitors don't support DDC)

However, the combination of (no EDID) + (low resolution) + (other VM signals) in a scoring approach is meaningful. As malware evasion techniques improve, EDID checks are a logical next layer.

**For sandbox designers:**
Setting a realistic resolution (1920×1080 or higher) is easy and eliminates the low-resolution detection vector. Injecting a realistic EDID is more complex but straightforward with QEMU's `edid=on` parameter.

The EDID manufacturer ID (`DEL` for Dell) and monitor model string can be verified by malware to check consistency with the claimed SMBIOS hardware. A Dell monitor connected to a claimed Dell OptiPlex is consistent; a "Generic PnP Monitor" is not.
