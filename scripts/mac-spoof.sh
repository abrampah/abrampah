#!/usr/bin/env bash
# scripts/mac-spoof.sh
# Sets a Dell OUI MAC address on the TAP/bridge interface before VM start.
# Real Dell OptiPlex NICs use these OUI prefixes; VM defaults (52:54:00, etc.)
# are trivially detected by WMI queries and raw MAC inspection.
#
# Usage:
#   sudo bash scripts/mac-spoof.sh [interface] [--random]
#   sudo bash scripts/mac-spoof.sh tap0
#   sudo bash scripts/mac-spoof.sh tap0 --random
#
# Without --random, uses the deterministic MAC from vm/config.env.
# With --random, generates a fresh last-3-octet suffix each run.

set -euo pipefail

IFACE="${1:-tap0}"
RANDOM_SUFFIX="${2:-}"

# Dell Inc. OUI prefixes (verified against IEEE registry)
DELL_OUIS=(
    "00:14:22"
    "00:21:70"
    "00:22:19"
    "B8:CA:3A"
    "F8:DB:88"
    "18:03:73"
    "14:18:77"
)

# Deterministic last 3 octets (for reproducible demo/grading)
DEFAULT_SUFFIX="AB:CD:EF"

if [[ ! -d "/sys/class/net/${IFACE}" ]]; then
    echo "ERROR: Interface '${IFACE}' not found." >&2
    echo "       Available interfaces: $(ls /sys/class/net/ | tr '\n' ' ')" >&2
    exit 1
fi

if [[ -n "${RANDOM_SUFFIX}" && "${RANDOM_SUFFIX}" == "--random" ]]; then
    # Generate random last 3 octets (locally administered bit NOT set —
    # keeping bit 1 of first octet 0 makes it look like a real OUI)
    SUFFIX=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n' | \
             sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/' | tr '[:lower:]' '[:upper:]')
else
    SUFFIX="${DEFAULT_SUFFIX}"
fi

# Pick a random Dell OUI for variation
OUI="${DELL_OUIS[$((RANDOM % ${#DELL_OUIS[@]}))]}"
NEW_MAC="${OUI}:${SUFFIX}"

echo "[*] Interface:   ${IFACE}"
echo "[*] Old MAC:     $(cat /sys/class/net/${IFACE}/address 2>/dev/null || echo unknown)"
echo "[*] New MAC:     ${NEW_MAC} (Dell OUI: ${OUI})"

ip link set "${IFACE}" down
ip link set "${IFACE}" address "${NEW_MAC}"
ip link set "${IFACE}" up

ACTUAL_MAC=$(cat /sys/class/net/${IFACE}/address)
if [[ "${ACTUAL_MAC,,}" == "${NEW_MAC,,}" ]]; then
    echo "[+] MAC set successfully: ${ACTUAL_MAC}"
else
    echo "ERROR: MAC mismatch after set. Got: ${ACTUAL_MAC}" >&2
    exit 1
fi

# Log to session file for cross-referencing with detection test results
LOG_DIR="$(dirname "${BASH_SOURCE[0]}")/../detection-tests"
if [[ -d "${LOG_DIR}" ]]; then
    echo "$(date -Iseconds) mac-spoof iface=${IFACE} mac=${NEW_MAC}" >> "${LOG_DIR}/session.log"
fi
