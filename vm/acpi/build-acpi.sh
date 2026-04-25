#!/usr/bin/env bash
# vm/acpi/build-acpi.sh — Compile ACPI SSDT source to binary AML
# Requires: iasl (Intel ACPI compiler)
#   Ubuntu: apt install acpica-tools
#   Fedora: dnf install acpica-tools

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v iasl &>/dev/null; then
    echo "ERROR: iasl not found. Install acpica-tools:" >&2
    echo "       Ubuntu: sudo apt install acpica-tools" >&2
    echo "       Fedora: sudo dnf install acpica-tools" >&2
    exit 1
fi

DSL="${SCRIPT_DIR}/SSDT-fake-battery.dsl"
AML="${SCRIPT_DIR}/SSDT-fake-battery.aml"

echo "[*] Compiling ${DSL}..."
iasl -tc -p "${SCRIPT_DIR}/SSDT-fake-battery" "${DSL}"

if [[ -f "${AML}" ]]; then
    echo "[+] Built: ${AML}"
    echo "[+] SHA256: $(sha256sum "${AML}")"
else
    echo "ERROR: Compilation failed — ${AML} not produced." >&2
    exit 1
fi
