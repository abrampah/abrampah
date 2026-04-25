#!/usr/bin/env python3
"""
scripts/driver-rename.py

Patches VirtIO Windows driver .inf files to replace vendor strings
with plausible Intel/Samsung/Realtek identifiers BEFORE installation.

This is more reliable than post-install registry patching because:
- Strings baked into the INF appear in Device Manager's driver detail
- Windows Update may restore the originals from the original INF
- The INF is read during device enumeration, not just at install time

Usage:
    python3 scripts/driver-rename.py /path/to/extracted-virtio-win/
    python3 scripts/driver-rename.py /mnt/virtio-win/ --dry-run
    python3 scripts/driver-rename.py /mnt/virtio-win/ --restore

The script saves a .bak copy of each patched INF so changes are reversible.

Dependencies: none (stdlib only)
"""

import argparse
import re
import shutil
import sys
from pathlib import Path

# Replacement table: (pattern, replacement, description)
# Patterns are case-insensitive. Order matters — more specific first.
REPLACEMENTS = [
    # Network adapter
    (r"Red Hat VirtIO Ethernet Adapter",   "Intel(R) Ethernet Connection I219-V",  "NIC display name"),
    (r"VirtIO Ethernet Adapter",           "Intel(R) Ethernet Connection I219-V",  "NIC display name (short)"),
    # Storage controllers
    (r"Red Hat VirtIO SCSI pass-through controller",
                                           "Intel(R) RST Premium SCSI Controller", "SCSI passthrough"),
    (r"Red Hat VirtIO SCSI controller",    "Intel(R) RST SATA Controller",         "SCSI controller"),
    (r"VirtIO SCSI",                       "Intel(R) RST SCSI",                    "SCSI generic"),
    (r"Red Hat VirtIO Block Device",       "Samsung NVMe SSD Controller SM981",    "Block device"),
    # GPU
    (r"Red Hat VirtIO GPU DOD controller", "Intel(R) UHD Graphics 630",            "GPU DOD"),
    (r"Red Hat VirtIO GPU",                "Intel(R) UHD Graphics 630",            "GPU"),
    (r"VirtIO GPU",                        "Intel(R) UHD Graphics 630",            "GPU short"),
    # Input
    (r"VirtIO Input Driver",               "HID-compliant mouse",                  "Input driver"),
    (r"VirtIO Balloon Driver",             "Dell System Performance Monitor",      "Balloon"),
    (r"VirtIO RNG Device",                 "Intel(R) Hardware RNG",                "RNG"),
    (r"VirtIO Serial Driver",              "Standard Serial over Bluetooth link",  "Serial"),
    (r"VirtIO Socket Driver",              "Intel(R) VMD Controller",              "Socket"),
    # Vendor/company strings
    (r"Red Hat, Inc\.",                    "Intel Corporation",                    "Vendor name (with period)"),
    (r"Red Hat, Inc",                      "Intel Corporation",                    "Vendor name (no period)"),
    (r"Red Hat VirtIO",                    "Intel(R) Virtual",                     "Generic VirtIO prefix"),
    # Provider names in [Strings] sections
    (r'"Provider"\s*=\s*"Red Hat[^"]*"',   '"Provider"="Intel Corporation"',       "INF Provider string"),
    (r'Provider\s*=\s*"Red Hat[^"]*"',     'Provider="Intel Corporation"',         "INF Provider (unquoted key)"),
    # Catalog file references that might leak "virtio"
    (r'CatalogFile\s*=\s*virtio[-_]',      'CatalogFile=oem',                      "Catalog file name"),
]


def detect_encoding(path: Path) -> str:
    """Detect UTF-16 (common for Windows INF) vs UTF-8."""
    raw = path.read_bytes()
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return 'utf-16'
    if raw[:3] == b'\xef\xbb\xbf':
        return 'utf-8-sig'
    return 'utf-8'


def patch_inf(path: Path, dry_run: bool = False) -> int:
    """Patch a single INF file. Returns number of substitutions made."""
    enc = detect_encoding(path)
    try:
        content = path.read_text(encoding=enc, errors='replace')
    except Exception as e:
        print(f"  SKIP (read error): {path} — {e}")
        return 0

    original = content
    count = 0
    for pattern, replacement, desc in REPLACEMENTS:
        new_content, n = re.subn(pattern, replacement, content, flags=re.IGNORECASE)
        if n > 0:
            content = new_content
            count += n

    if count == 0:
        return 0

    if dry_run:
        print(f"  [DRY] Would patch {count} strings in: {path.name}")
        return count

    backup = path.with_suffix(path.suffix + '.bak')
    if not backup.exists():
        shutil.copy2(path, backup)

    path.write_text(content, encoding=enc)
    print(f"  [+] Patched {count} strings: {path.name}")
    return count


def restore_inf(path: Path) -> bool:
    """Restore an INF from its .bak copy."""
    backup = path.with_suffix(path.suffix + '.bak')
    if backup.exists():
        shutil.copy2(backup, path)
        backup.unlink()
        print(f"  [+] Restored: {path.name}")
        return True
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Patch VirtIO driver INF files to hide VM origin"
    )
    parser.add_argument("virtio_dir", help="Path to extracted virtio-win directory")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be changed without modifying files")
    parser.add_argument("--restore", action="store_true",
                        help="Restore .inf files from .bak backups")
    args = parser.parse_args()

    virtio_dir = Path(args.virtio_dir)
    if not virtio_dir.is_dir():
        print(f"ERROR: Not a directory: {virtio_dir}", file=sys.stderr)
        sys.exit(1)

    inf_files = list(virtio_dir.rglob("*.inf"))
    if not inf_files:
        print(f"ERROR: No .inf files found under {virtio_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"[*] {'Restoring' if args.restore else 'Patching'} {len(inf_files)} INF files under {virtio_dir}")

    total_changes = 0
    total_files = 0
    for inf in sorted(inf_files):
        if args.restore:
            if restore_inf(inf):
                total_files += 1
        else:
            n = patch_inf(inf, dry_run=args.dry_run)
            if n > 0:
                total_changes += n
                total_files += 1

    if args.restore:
        print(f"\n[+] Restored {total_files} files.")
    else:
        mode = "Would patch" if args.dry_run else "Patched"
        print(f"\n[+] {mode} {total_files} files, {total_changes} total substitutions.")
        if not args.dry_run:
            print("[!] Rebuild the virtio-win ISO or use the directory directly as a share.")
            print("[!] Run 'python3 driver-rename.py <dir> --restore' to undo changes.")


if __name__ == "__main__":
    main()
