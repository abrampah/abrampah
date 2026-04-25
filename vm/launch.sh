#!/usr/bin/env bash
# vm/launch.sh — QEMU/KVM launch script with anti-VM-detection configuration
# Run as root (required for TAP network and KVM access)
# See vm/config.env for path configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

# Verify KVM is available
if [[ ! -c /dev/kvm ]]; then
    echo "ERROR: /dev/kvm not found. Bare-metal host with KVM is required." >&2
    echo "       For nested virt: modprobe kvm_intel nested=1" >&2
    exit 1
fi

# Copy OVMF VARS if not already done (VARS is writable per-VM state)
if [[ ! -f "${OVMF_VARS}" ]]; then
    echo "[*] Copying OVMF VARS template..."
    cp "${OVMF_VARS_TEMPLATE}" "${OVMF_VARS}"
fi

# Build ACPI table if missing
if [[ "${STEALTH_ACPI}" == "1" && ! -f "${ACPI_AML}" ]]; then
    echo "[*] Building ACPI SSDT..."
    bash "${SCRIPT_DIR}/acpi/build-acpi.sh"
fi

# Build ACPI flag
ACPI_FLAG=""
if [[ "${STEALTH_ACPI}" == "1" && -f "${ACPI_AML}" ]]; then
    ACPI_FLAG="-acpitable file=${ACPI_AML}"
fi

# Determine boot mode: installer vs existing disk
BOOT_FLAGS="-boot order=dc"
CDROM_FLAGS=""
if [[ -f "${WIN_ISO}" ]]; then
    CDROM_FLAGS="-drive file=${WIN_ISO},media=cdrom,index=0,readonly=on"
fi
VIRTIO_FLAG=""
if [[ -f "${VIRTIO_ISO}" ]]; then
    VIRTIO_FLAG="-drive file=${VIRTIO_ISO},media=cdrom,index=1,readonly=on"
fi

# Display mode: GL passthrough (default) vs basic VirtIO
# GL passthrough makes WebGL renderer reflect the host GPU — required to pass
# Proctorio's WebGL renderer check. Falls back gracefully if virgl unavailable.
#
# Override with: DISPLAY_MODE=basic bash vm/launch.sh
DISPLAY_MODE="${DISPLAY_MODE:-gl}"
if [[ "${DISPLAY_MODE}" == "gl" ]]; then
    if glxinfo 2>/dev/null | grep -q "OpenGL version"; then
        DISPLAY_FLAGS="-device virtio-vga-gl -display gtk,gl=on"
        echo "[*] Display mode: VirtIO-GL (host GPU passthrough via virgl)"
    else
        DISPLAY_FLAGS="-device virtio-vga -display gtk"
        echo "[!] Warning: glxinfo not found or OpenGL unavailable. Falling back to basic display."
        echo "    WebGL renderer will expose VirtIO strings. Use DISPLAY_MODE=basic to suppress this warning."
    fi
else
    DISPLAY_FLAGS="-device virtio-vga -display gtk"
    echo "[*] Display mode: basic VirtIO (no GL passthrough)"
fi

echo "[*] Starting Windows VM with anti-detection configuration..."

exec qemu-system-x86_64 \

    # ----------------------------------------------------------------
    # Machine: Q35 chipset (modern Intel — matches OptiPlex 7090)
    # smm=on required for Secure Boot / Windows 11 TPM requirements
    # ----------------------------------------------------------------
    -machine q35,accel=kvm,smm=on \
    -m "${VM_RAM}" \
    -smp "${VM_CORES}",cores="${VM_CORES_PER_SOCKET}",threads="${VM_THREADS}",sockets="${VM_SOCKETS}" \

    # ----------------------------------------------------------------
    # CPU: host-passthrough with hypervisor presence hidden
    #   hypervisor=off  — clears CPUID leaf 1 ECX bit 31 (hypervisor present)
    #   kvm=off         — hides KVM CPUID leaves (0x40000000-0x40000001)
    #   +invtsc         — invariant TSC (reduces RDTSC timing delta)
    #   +rdtscp         — RDTSCP instruction (expected on real i7-10700)
    #   hv-vendor-id    — overrides Hyper-V leaf vendor string
    # ----------------------------------------------------------------
    -cpu host,hypervisor=off,kvm=off,+invtsc,+rdtscp,hv-vendor-id=AuthenticAMD \

    # ----------------------------------------------------------------
    # UEFI Firmware: OVMF (EDK2) — avoids SeaBIOS BOCHS vendor strings
    # ----------------------------------------------------------------
    -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
    -drive if=pflash,format=raw,file="${OVMF_VARS}" \

    # ----------------------------------------------------------------
    # Storage: NVMe with Samsung model/serial strings
    # SATA bus used for optical drives — consistent with real hardware
    # ----------------------------------------------------------------
    -drive file="${DISK_IMAGE}",format=qcow2,if=none,id=drive0,cache=writeback,discard=unmap \
    -device nvme,drive=drive0,serial="S4EWNX0R123456",model="Samsung SSD 970 EVO Plus 1TB" \
    ${CDROM_FLAGS} \
    ${VIRTIO_FLAG} \
    -boot order=dc \

    # ----------------------------------------------------------------
    # Network: e1000e (Intel NIC ubiquitous in Dell OptiPlex)
    # MAC set to Dell OUI prefix via mac-spoof.sh before this script runs
    # ----------------------------------------------------------------
    -netdev tap,id=net0,ifname="${TAP_IFACE}",script=no,downscript=no \
    -device e1000e,netdev=net0,mac="${MAC_ADDR}" \

    # ----------------------------------------------------------------
    # Display: virtio-vga-gl with OpenGL passthrough (default mode)
    #   gl=on passes the host GPU through VirtIO-GPU/virgl protocol.
    #   Inside the VM, the WebGL renderer string reflects the host GPU
    #   (e.g., "ANGLE (Intel, Intel(R) UHD Graphics 630, OpenGL 4.6)")
    #   rather than a Red Hat/VirtIO/llvmpipe string — critical for
    #   defeating Proctorio's WebGL renderer check.
    #
    #   Requires host support: glxinfo | grep "OpenGL version" (need 3.3+)
    #   Fallback: DISPLAY_MODE=basic bash vm/launch.sh  (no GL passthrough)
    # ----------------------------------------------------------------
    ${DISPLAY_FLAGS} \

    # ----------------------------------------------------------------
    # Clock: localtime base, host clock, slew drift correction
    #   hpet=no         — HPET exposes hypervisor timing anomalies
    #   kvmclock=no     — KVM paravirt clock is a direct VM indicator
    #   hypervclock=no  — Hyper-V synthetic timer — not expected on Dell
    # ----------------------------------------------------------------
    -rtc base=localtime,clock=host,driftfix=slew \
    -no-hpet \

    # ----------------------------------------------------------------
    # SMBIOS: Dell OptiPlex 7090 identity
    # Type 0  — BIOS (Dell firmware version)
    # Type 1  — System (manufacturer, model, serial, UUID)
    # Type 2  — Baseboard
    # Type 3  — Chassis
    # Type 4  — Processor
    # Type 17 — Memory device
    # ----------------------------------------------------------------
    -smbios type=0,vendor="Dell Inc.",version="1.18.0",date="11/02/2022",release=1.18 \
    -smbios type=1,manufacturer="Dell Inc.",product="OptiPlex 7090",version="Not Specified",serial="ABCD1234",uuid="44454C4C-4700-1052-8050-C3C04F325931",sku="OptiPlex 7090",family="OptiPlex" \
    -smbios type=2,manufacturer="Dell Inc.",product="0TT6JF",version="A01",serial="CN7692370D05F5." \
    -smbios type=3,manufacturer="Dell Inc.",version="Not Specified",serial="ABCD1234" \
    -smbios type=4,sock_pfx="CPU",manufacturer="Intel",version="Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz",max-speed=4800,current-speed=2900 \
    -smbios type=17,manufacturer="Samsung",serial="87654321",asset="Not Specified",part="M378A1K43EB2-CWE",speed=3200 \

    # ----------------------------------------------------------------
    # ACPI: custom SSDT (fake battery, Dell OEM IDs)
    # ----------------------------------------------------------------
    ${ACPI_FLAG} \

    # ----------------------------------------------------------------
    # USB: realistic hub with human-presence signal
    # ----------------------------------------------------------------
    -device usb-ehci,id=ehci \
    -device usb-hub,bus=ehci.0 \
    -device usb-tablet \

    # ----------------------------------------------------------------
    # Disable serial/parallel — BOCHS COM port strings are detectable
    # ----------------------------------------------------------------
    -serial none \
    -parallel none \

    # ----------------------------------------------------------------
    # Management: QEMU monitor on Unix socket (not stdio — avoids leaking
    # monitor prompts if stdout is captured by a logging framework)
    # ----------------------------------------------------------------
    -monitor unix:"${MONITOR_SOCK}",server,nowait \
    -pidfile "${PID_FILE}" \

    # TPM (software — required for Windows 11)
    -chardev socket,id=chrtpm,path=/tmp/swtpm-sock \
    -tpmdev emulator,id=tpm0,chardev=chrtpm \
    -device tpm-tis,tpmdev=tpm0 \

    "$@"
