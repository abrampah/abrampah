#!/usr/bin/env bash
# scripts/snapshot.sh
# Creates a named libvirt snapshot of the windows-stealth VM.
# Run after all post-install patching is complete and verified.
#
# Usage:
#   bash scripts/snapshot.sh [snapshot-name] [description]
#   bash scripts/snapshot.sh post-patch-clean "All anti-detection patches applied"

set -euo pipefail

DOMAIN="windows-stealth"
SNAP_NAME="${1:-post-patch-clean}"
SNAP_DESC="${2:-Anti-detection patches applied. Detection tools run and documented.}"

if ! command -v virsh &>/dev/null; then
    echo "ERROR: virsh not found. Install libvirt-clients." >&2
    exit 1
fi

if ! virsh dominfo "${DOMAIN}" &>/dev/null; then
    echo "ERROR: Domain '${DOMAIN}' not found." >&2
    echo "       Import it first: virsh define vm/windows-stealth.xml" >&2
    exit 1
fi

STATE=$(virsh domstate "${DOMAIN}")
echo "[*] Domain: ${DOMAIN} (state: ${STATE})"

if [[ "${STATE}" != "shut off" ]]; then
    echo "[!] VM is running. Snapshot will be disk-only (live snapshot)."
    echo "    For a clean snapshot, shut down the VM first."
    read -r -p "    Continue with live snapshot? [y/N] " ans
    [[ "${ans,,}" == "y" ]] || { echo "Aborted."; exit 0; }

    virsh snapshot-create-as \
        --domain "${DOMAIN}" \
        --name "${SNAP_NAME}" \
        --description "${SNAP_DESC}" \
        --disk-only \
        --atomic
else
    virsh snapshot-create-as \
        --domain "${DOMAIN}" \
        --name "${SNAP_NAME}" \
        --description "${SNAP_DESC}"
fi

echo "[+] Snapshot '${SNAP_NAME}' created."
echo ""
echo "Revert with:  virsh snapshot-revert ${DOMAIN} ${SNAP_NAME}"
echo "List all:     virsh snapshot-list ${DOMAIN}"
