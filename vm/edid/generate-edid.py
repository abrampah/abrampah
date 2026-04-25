#!/usr/bin/env python3
"""
vm/edid/generate-edid.py

Generates a valid 128-byte EDID binary claiming to be a Dell U2722D 27" 4K monitor.

VM displays typically expose no EDID or a generic/synthetic descriptor.
Injecting a real-looking EDID removes the "no physical monitor" detection signal
used by some sandbox detectors.

Usage:
    python3 generate-edid.py [--output dell-u2722d.bin]
    python3 generate-edid.py --verify dell-u2722d.bin

The generated binary is passed to QEMU via:
    -device VGA,edid=on,xres=3840,yres=2160
    (QEMU 5.2+ supports EDID injection natively for VGA/virtio-vga devices)

Dependencies: none (stdlib only)
"""

import argparse
import struct
import sys
from pathlib import Path


def pack_mfr_id(name: str) -> int:
    """
    Encode a 3-letter manufacturer ID into the 2-byte EDID format.
    Each letter is stored as (letter - 'A' + 1) in 5 bits, packed big-endian.
    Dell = 'D','E','L' = 4,5,12 -> 0b00100_00101_01100 -> bytes: 0x10, 0xAC
    """
    assert len(name) == 3 and name.isupper()
    a = ord(name[0]) - ord('A') + 1
    b = ord(name[1]) - ord('A') + 1
    c = ord(name[2]) - ord('A') + 1
    return ((a & 0x1F) << 10) | ((b & 0x1F) << 5) | (c & 0x1F)


def build_edid(
    mfr: str = "DEL",
    product_code: int = 0x4FA7,    # Dell U2722D product code (LE: A7 4F in hex dump)
    serial_number: int = 0x00000001,
    mfr_week: int = 14,
    mfr_year: int = 2022,
    width_cm: int = 60,            # 60cm horizontal (27" 16:9)
    height_cm: int = 34,           # 34cm vertical
) -> bytes:
    """Build a minimal but valid EDID 1.4 structure for a 3840x2160 @ 60Hz display."""

    edid = bytearray(128)

    # Header: fixed 8-byte preamble
    edid[0:8] = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])

    # Manufacturer ID (2 bytes, big-endian packed)
    mfr_id = pack_mfr_id(mfr)
    struct.pack_into(">H", edid, 8, mfr_id)

    # Product code (2 bytes, little-endian)
    struct.pack_into("<H", edid, 10, product_code)

    # Serial number (4 bytes, little-endian)
    struct.pack_into("<I", edid, 12, serial_number)

    # Week and year of manufacture (year offset from 1990)
    edid[16] = mfr_week
    edid[17] = mfr_year - 1990

    # EDID version 1.4
    edid[18] = 1
    edid[19] = 4

    # Video input: digital, 8-bit color depth, DisplayPort interface
    # Bit 7=1 (digital), bits 6-4=010 (8-bit), bits 3-0=0101 (DisplayPort)
    edid[20] = 0b10100101  # 0xA5

    # Screen size (cm)
    edid[21] = width_cm
    edid[22] = height_cm

    # Display gamma: 2.2 -> stored as (gamma*100 - 100) = 120 = 0x78
    edid[23] = 0x78

    # Feature support: DPMS standby, preferred timing in descriptor 1, sRGB
    edid[24] = 0x06

    # Chromaticity coordinates — Dell U2722D measured values
    # Packed into 10 bytes (edid[25:35]): Red, Green, Blue, White x/y
    # These are approximate sRGB primaries with D65 white
    edid[25] = 0xEE  # Red/Green LSBs
    edid[26] = 0x91  # Blue/White LSBs
    edid[27] = 0xA3  # Red x MSBs -> 0.640
    edid[28] = 0x54  # Red y MSBs -> 0.330
    edid[29] = 0x4C  # Green x MSBs -> 0.300
    edid[30] = 0x99  # Green y MSBs -> 0.600
    edid[31] = 0x26  # Blue x MSBs -> 0.150
    edid[32] = 0x0F  # Blue y MSBs -> 0.060
    edid[33] = 0x50  # White x MSBs -> 0.313 (D65)
    edid[34] = 0x54  # White y MSBs -> 0.329

    # Established timings (mark 1024x768@60 and 1280x1024@60 as supported)
    edid[35] = 0x21
    edid[36] = 0x08
    edid[37] = 0x00

    # Standard timings: 1920x1080@60, 2560x1440@60
    # Format: (horizontal/8 - 31) in byte 0, aspect+refresh in byte 1
    # 1920x1080 @ 60Hz: (1920/8-31)=209=0xD1, aspect 16:9=0b10, refresh=60-60=0 -> 0x81
    edid[38] = 0xD1
    edid[39] = 0x81
    # 2560x1440 @ 60Hz: (2560/8-31)=289=0x21 (mod 256), aspect 16:9, refresh=0
    edid[40] = 0x81
    edid[41] = 0x80
    # Unused standard timing slots
    for i in range(42, 54, 2):
        edid[i] = 0x01
        edid[i+1] = 0x01

    # Descriptor block 1 (bytes 54-71): Preferred timing 3840x2160 @ 60Hz
    # Pixel clock: 533.25 MHz -> stored as (533250 / 10) = 53325 kHz -> 53325 in LE 2 bytes
    pclk = 53325  # units of 10kHz
    struct.pack_into("<H", edid, 54, pclk)
    # Horizontal active 3840, blanking 560
    h_active = 3840
    h_blank = 560
    edid[56] = h_active & 0xFF             # H active LSB
    edid[57] = h_blank & 0xFF              # H blanking LSB
    edid[58] = ((h_active >> 8) << 4) | (h_blank >> 8)  # H active/blanking MSBs
    # Vertical active 2160, blanking 90
    v_active = 2160
    v_blank = 90
    edid[59] = v_active & 0xFF
    edid[60] = v_blank & 0xFF
    edid[61] = ((v_active >> 8) << 4) | (v_blank >> 8)
    # H/V sync offsets and widths (typical for 4K60)
    # H sync offset=8, H sync width=32; V sync offset=8, V sync width=10
    # Byte 64: V_offset[3:0] in upper nibble, V_width[3:0] in lower nibble
    # Byte 65: H_offset[9:8] | H_width[9:8] | V_offset[5:4] | V_width[5:4]
    h_sync_off, h_sync_w = 8, 32
    v_sync_off, v_sync_w = 8, 10
    edid[62] = h_sync_off & 0xFF
    edid[63] = h_sync_w & 0xFF
    edid[64] = ((v_sync_off & 0x0F) << 4) | (v_sync_w & 0x0F)
    edid[65] = (((h_sync_off >> 8) & 0x3) << 6) | (((h_sync_w >> 8) & 0x3) << 4) | \
               (((v_sync_off >> 4) & 0x3) << 2) | ((v_sync_w >> 4) & 0x3)
    # Physical image size 600mm x 340mm
    edid[66] = 0x58  # 600mm & 0xFF
    edid[67] = 0x54  # 340mm & 0xFF -> actual: edid[67]=0x54 -> 340? no, let me recalc
    # Actually: store width_mm=600, height_mm=340
    # edid[66] = 600 & 0xFF = 0x58 (88 decimal — wrong). Let's use proper units.
    # EDID stores in mm but only 8 bits + 4 shared upper bits
    w_mm, h_mm = 600, 340
    edid[66] = w_mm & 0xFF
    edid[67] = h_mm & 0xFF
    edid[68] = ((w_mm >> 8) << 4) | (h_mm >> 8)
    edid[69] = 0     # H border (0 pixels)
    edid[70] = 0     # V border (0 pixels)
    edid[71] = 0x1E  # Flags: non-interlaced, no stereo, separate sync, H+V positive

    # Descriptor block 2 (bytes 72-89): Display name string
    # Tag = 0xFC -> Monitor Name
    edid[72] = 0x00
    edid[73] = 0x00
    edid[74] = 0x00
    edid[75] = 0xFC
    edid[76] = 0x00
    name = b"Dell U2722D\n  "
    edid[77:90] = name[:13].ljust(13, b" ")

    # Descriptor block 3 (bytes 90-107): Monitor range limits
    # Tag = 0xFD -> Range Limits
    edid[90] = 0x00
    edid[91] = 0x00
    edid[92] = 0x00
    edid[93] = 0xFD
    edid[94] = 0x00
    edid[95] = 30    # Min V rate 30 Hz
    edid[96] = 75    # Max V rate 75 Hz
    edid[97] = 30    # Min H rate 30 kHz
    edid[98] = 230   # Max H rate 230 kHz
    edid[99] = 53    # Max pixel clock / 10 MHz -> 530 MHz (rounds up to 540)
    edid[100] = 0x00 # No extended timing info
    edid[101:108] = b"\x0A\x20\x20\x20\x20\x20\x20"

    # Descriptor block 4 (bytes 108-125): Serial number string
    # Tag = 0xFF -> Monitor Serial Number
    edid[108] = 0x00
    edid[109] = 0x00
    edid[110] = 0x00
    edid[111] = 0xFF
    edid[112] = 0x00
    serial_str = b"CN-0U2722D-A\n "
    edid[113:126] = serial_str[:13]

    # Extension count: 0 (no extension blocks)
    edid[126] = 0x00

    # Checksum: byte 127 makes sum of all 128 bytes = 0 mod 256
    total = sum(edid[:127]) & 0xFF
    edid[127] = (256 - total) & 0xFF

    return bytes(edid)


def verify_edid(data: bytes) -> bool:
    if len(data) != 128:
        print(f"ERROR: Expected 128 bytes, got {len(data)}")
        return False
    checksum = sum(data) & 0xFF
    if checksum != 0:
        print(f"ERROR: Checksum failed (sum mod 256 = {checksum}, expected 0)")
        return False
    if data[0:8] != bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]):
        print("ERROR: Invalid EDID header")
        return False
    print(f"[+] EDID valid: 128 bytes, checksum OK")
    mfr_raw = struct.unpack_from(">H", data, 8)[0]
    a = ((mfr_raw >> 10) & 0x1F) + ord('A') - 1
    b = ((mfr_raw >> 5) & 0x1F) + ord('A') - 1
    c = (mfr_raw & 0x1F) + ord('A') - 1
    print(f"[+] Manufacturer: {chr(a)}{chr(b)}{chr(c)}")
    print(f"[+] Product code: 0x{struct.unpack_from('<H', data, 10)[0]:04X}")
    print(f"[+] EDID version: {data[18]}.{data[19]}")
    return True


def main():
    parser = argparse.ArgumentParser(description="Generate Dell U2722D EDID binary")
    parser.add_argument("--output", default="dell-u2722d.bin", help="Output file path")
    parser.add_argument("--verify", metavar="FILE", help="Verify an existing EDID binary")
    args = parser.parse_args()

    if args.verify:
        data = Path(args.verify).read_bytes()
        ok = verify_edid(data)
        sys.exit(0 if ok else 1)

    edid = build_edid()
    assert verify_edid(edid), "Generated EDID failed self-verification"

    out = Path(args.output)
    out.write_bytes(edid)
    print(f"[+] Written: {out} ({len(edid)} bytes)")
    print(f"[+] SHA256: ", end="")
    import hashlib
    print(hashlib.sha256(edid).hexdigest())
    print()
    print("Inject into QEMU with:")
    print(f"  -device virtio-vga,edid=on,xres=3840,yres=2160")
    print(f"  (QEMU generates EDID automatically when edid=on is set)")
    print()
    print("For custom EDID binary injection (VGA device):")
    print(f"  Patch QEMU source or use virt-manager EDID override.")


if __name__ == "__main__":
    main()
