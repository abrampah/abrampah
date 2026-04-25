#!/usr/bin/env bash
# vm/launch.sh — QEMU/KVM Windows VM launcher with anti-detection configuration.
# Run as root or with sudo.
# Edit vm/config.env before running.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

# ── Preflight checks ────────────────────────────────────────────────────────
if [[ ! -c /dev/kvm ]]; then
    echo "ERROR: /dev/kvm not found."
    echo "  Your host must be bare-metal Linux with KVM enabled."
    echo "  If on a nested VM: modprobe kvm_intel nested=1"
    exit 1
fi

if [[ ! -f "${DISK_IMAGE}" ]]; then
    echo "ERROR: Disk image not found: ${DISK_IMAGE}"
    echo "  Create it first: sudo qemu-img create -f qcow2 ${DISK_IMAGE} 80G"
    exit 1
fi

# ── OVMF firmware ────────────────────────────────────────────────────────────
if [[ ! -f "${OVMF_VARS}" ]]; then
    echo "[*] Copying OVMF VARS template..."
    mkdir -p "$(dirname "${OVMF_VARS}")"
    cp "${OVMF_VARS_TEMPLATE}" "${OVMF_VARS}"
fi

# ── ACPI table ────────────────────────────────────────────────────────────────
if [[ "${STEALTH_ACPI}" == "1" && ! -f "${ACPI_AML}" ]]; then
    echo "[*] Building ACPI SSDT (fake battery)..."
    bash "${SCRIPT_DIR}/acpi/build-acpi.sh"
fi

ACPI_ARGS=()
if [[ "${STEALTH_ACPI}" == "1" && -f "${ACPI_AML}" ]]; then
    ACPI_ARGS=(-acpitable "file=${ACPI_AML}")
fi

# ── ISO drives (optional — skip if not present) ──────────────────────────────
ISO_ARGS=()
if [[ -f "${WIN_ISO}" ]]; then
    ISO_ARGS+=(-drive "file=${WIN_ISO},media=cdrom,index=0,readonly=on")
fi
if [[ -f "${VIRTIO_ISO}" ]]; then
    ISO_ARGS+=(-drive "file=${VIRTIO_ISO},media=cdrom,index=1,readonly=on")
fi

# ── Display mode ─────────────────────────────────────────────────────────────
# GL mode (default): host GPU passed through via virgl — WebGL renderer inside
# the VM shows the host GPU string, not a VirtIO/llvmpipe string.
# Required to pass Proctorio's WebGL check.
# Fallback: DISPLAY_MODE=basic bash vm/launch.sh
DISPLAY_MODE="${DISPLAY_MODE:-gl}"
DISPLAY_ARGS=()
if [[ "${DISPLAY_MODE}" == "gl" ]] && glxinfo 2>/dev/null | grep -q "OpenGL version"; then
    DISPLAY_ARGS=(-device virtio-vga-gl -display gtk,gl=on)
    echo "[*] Display: VirtIO-GL (host GPU via virgl)"
else
    DISPLAY_ARGS=(-device virtio-vga -display gtk)
    [[ "${DISPLAY_MODE}" == "gl" ]] && echo "[!] virgl unavailable — using basic display (WebGL will show VirtIO strings)"
fi

# ── TPM (required for Windows 11) ────────────────────────────────────────────
# swtpm must already be running. Start it with:
#   mkdir -p /tmp/swtpm-state
#   swtpm socket --tpmstate dir=/tmp/swtpm-state --ctrl type=unixio,path=/tmp/swtpm-sock --tpm2 --daemon
TPM_ARGS=()
if [[ -S /tmp/swtpm-sock ]]; then
    TPM_ARGS=(
        -chardev socket,id=chrtpm,path=/tmp/swtpm-sock
        -tpmdev emulator,id=tpm0,chardev=chrtpm
        -device tpm-tis,tpmdev=tpm0
    )
    echo "[*] TPM: swtpm socket found"
else
    echo "[!] TPM: /tmp/swtpm-sock not found — Windows 11 install requires TPM."
    echo "    Run: mkdir -p /tmp/swtpm-state && swtpm socket --tpmstate dir=/tmp/swtpm-state --ctrl type=unixio,path=/tmp/swtpm-sock --tpm2 --daemon"
fi

echo "[*] Launching VM..."

exec qemu-system-x86_64 \
    -machine q35,accel=kvm,smm=on \
    -m "${VM_RAM}" \
    -smp "${VM_CORES}",cores="${VM_CORES_PER_SOCKET}",threads="${VM_THREADS}",sockets="${VM_SOCKETS}" \
    -cpu host,hypervisor=off,kvm=off,+invtsc,+rdtscp,hv-vendor-id=AuthenticAMD \
    -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
    -drive if=pflash,format=raw,file="${OVMF_VARS}" \
    -drive file="${DISK_IMAGE}",format=qcow2,if=none,id=drive0,cache=writeback,discard=unmap \
    -device nvme,drive=drive0,serial="S4EWNX0R123456",model="Samsung SSD 970 EVO Plus 1TB" \
    "${ISO_ARGS[@]+"${ISO_ARGS[@]}"}" \
    -boot order=dc \
    -netdev tap,id=net0,ifname="${TAP_IFACE}",script=no,downscript=no \
    -device e1000e,netdev=net0,mac="${MAC_ADDR}" \
    "${DISPLAY_ARGS[@]}" \
    -rtc base=localtime,clock=host,driftfix=slew \
    -no-hpet \
    -global kvm-pit.lost_tick_policy=delay \
    -smbios type=0,vendor="Dell Inc.",version="1.18.0",date="11/02/2022",release=1.18 \
    -smbios type=1,manufacturer="Dell Inc.",product="OptiPlex 7090",version="Not Specified",serial="ABCD1234",uuid="44454C4C-4700-1052-8050-C3C04F325931",sku="OptiPlex 7090",family="OptiPlex" \
    -smbios type=2,manufacturer="Dell Inc.",product="0TT6JF",version="A01",serial="CN7692370D05F5." \
    -smbios type=3,manufacturer="Dell Inc.",version="Not Specified",serial="ABCD1234" \
    -smbios type=4,sock_pfx="CPU",manufacturer="Intel",version="Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz",max-speed=4800,current-speed=2900 \
    -smbios type=17,manufacturer="Samsung",serial="87654321",asset="Not Specified",part="M378A1K43EB2-CWE",speed=3200 \
    "${ACPI_ARGS[@]+"${ACPI_ARGS[@]}"}" \
    "${TPM_ARGS[@]+"${TPM_ARGS[@]}"}" \
    -device usb-ehci,id=ehci \
    -device usb-hub,bus=ehci.0 \
    -device usb-tablet \
    -serial none \
    -parallel none \
    -monitor unix:"${MONITOR_SOCK}",server,nowait \
    -pidfile "${PID_FILE}" \
    "$@"
