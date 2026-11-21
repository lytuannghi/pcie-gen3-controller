#!/usr/bin/env python3
"""
Physical Layout Generator for PCIe Gen 3 (8 GT/s) Controller Subsystem.
Generates binary GDSII layout viewable in KLayout without external dependencies.
"""

import struct
import os
import time

class GDSWriter:
    def __init__(self, filename, libname="PCIE_GEN3_LIB"):
        self.f = open(filename, "wb")
        self.libname = libname
        self._write_header()

    def _write_record(self, rec_type, data_type, data=b""):
        rec_len = len(data) + 4
        self.f.write(struct.pack(">HH", rec_len, (rec_type << 8) | data_type))
        if data:
            self.f.write(data)

    def _write_header(self):
        self._write_record(0x00, 0x02, struct.pack(">H", 600))
        t = time.localtime()
        time_data = struct.pack(">12H", t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec,
                                       t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)
        self._write_record(0x01, 0x02, time_data)
        libname_bytes = self.libname.encode("ascii")
        if len(libname_bytes) % 2 != 0:
            libname_bytes += b"\0"
        self._write_record(0x02, 0x06, libname_bytes)
        self._write_record(0x03, 0x05, struct.pack(">dd", 0.001, 1e-9))

    def bgn_str(self, strname):
        t = time.localtime()
        time_data = struct.pack(">12H", t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec,
                                       t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)
        self._write_record(0x05, 0x02, time_data)
        str_bytes = strname.encode("ascii")
        if len(str_bytes) % 2 != 0:
            str_bytes += b"\0"
        self._write_record(0x06, 0x06, str_bytes)

    def end_str(self):
        self._write_record(0x07, 0x00)

    def add_box(self, layer, datatype, x1, y1, x2, y2):
        self._write_record(0x08, 0x00)
        self._write_record(0x0D, 0x02, struct.pack(">H", layer))
        self._write_record(0x0E, 0x02, struct.pack(">H", datatype))
        pts = [
            (int(x1 * 1000), int(y1 * 1000)),
            (int(x2 * 1000), int(y1 * 1000)),
            (int(x2 * 1000), int(y2 * 1000)),
            (int(x1 * 1000), int(y2 * 1000)),
            (int(x1 * 1000), int(y1 * 1000))
        ]
        xy_data = b"".join(struct.pack(">ii", p[0], p[1]) for p in pts)
        self._write_record(0x10, 0x03, xy_data)
        self._write_record(0x11, 0x00)

    def close(self):
        self._write_record(0x04, 0x00)
        self.f.close()


def generate_pcie_layout():
    out_dir = "layout/gds"
    os.makedirs(out_dir, exist_ok=True)
    gds_path = os.path.join(out_dir, "pcie_gen3_controller.gds")

    gds = GDSWriter(gds_path, libname="PCIE_GEN3_CONTROLLER")
    gds.bgn_str("pcie_gen3_controller_top")

    # Layer Conventions:
    # Layer 100: PR Boundary (1500um x 1500um)
    # Layer 108: I/O Pads (70um x 80um)
    # Layer 21: Metal 1 (Standard Cells)
    # Layer 31: Metal 2 (Power Stripes Vertical)
    # Layer 41: Metal 3 (Power Stripes Horizontal)
    # Layer 51: Metal 4 (Power Ring & Global Clock Trunk)

    # 1. Die Boundary
    gds.add_box(100, 0, 0, 0, 1500, 1500)

    # 2. I/O Pad Ring (64 pads)
    pad_w = 60
    pad_h = 80
    for i in range(16):
        x = 120 + i * 80
        gds.add_box(108, 0, x, 10, x + pad_w, 10 + pad_h)       # Bottom
        gds.add_box(108, 0, x, 1410, x + pad_w, 1410 + pad_h)  # Top
    for i in range(16):
        y = 120 + i * 80
        gds.add_box(108, 0, 10, y, 10 + pad_h, y + pad_w)       # Left
        gds.add_box(108, 0, 1410, y, 1410 + pad_h, y + pad_w)  # Right

    # 3. Dual Power Ring (Metal 4 / Metal 3)
    gds.add_box(51, 0, 125, 125, 1375, 145)
    gds.add_box(51, 0, 125, 1355, 1375, 1375)
    gds.add_box(51, 0, 125, 125, 145, 1375)
    gds.add_box(51, 0, 1355, 125, 1375, 1375)

    # 4. Functional IP Macros Floorplan:
    # Macro A: Transaction Layer (TLP Gen & Parse - 450um x 400um)
    gds.add_box(100, 1, 180, 180, 650, 580)
    gds.add_box(21, 0, 190, 190, 400, 370) # TLP Generator
    gds.add_box(21, 0, 410, 190, 640, 370) # TLP Parser
    gds.add_box(21, 0, 190, 380, 640, 570) # Virtual Channel Buffers

    # Macro B: Data Link Layer (DLL - 450um x 350um)
    gds.add_box(100, 2, 690, 180, 1320, 580)
    gds.add_box(21, 0, 700, 190, 990, 370)  # LCRC-32 Parallel Generator
    gds.add_box(21, 0, 1000, 190, 1310, 370) # Sequence Number Logic
    gds.add_box(21, 0, 700, 380, 1310, 570) # ACK/NAK & Replay Buffer SRAM

    # Macro C: Physical Layer & PIPE Interface (450um x 380um)
    gds.add_box(100, 3, 180, 620, 650, 1000)
    gds.add_box(21, 0, 190, 630, 410, 800)  # LTSSM FSM
    gds.add_box(21, 0, 420, 630, 640, 800)  # 128b/130b Scrambler
    gds.add_box(21, 0, 190, 810, 640, 990)  # PIPE 4.3 SerDes Interface

    # Macro D: Scatter-Gather DMA Subsystem (600um x 380um)
    gds.add_box(100, 4, 690, 620, 1320, 1000)
    gds.add_box(21, 0, 700, 630, 990, 800)  # Descriptor Ring Engine
    gds.add_box(21, 0, 1000, 630, 1310, 800) # AXI4 Master Bridge
    gds.add_box(21, 0, 700, 810, 1310, 990) # Data FIFOs & Aligners

    # Macro E: Configuration Space & Status Registers
    gds.add_box(100, 5, 180, 1040, 1320, 1330)
    gds.add_box(21, 0, 190, 1050, 740, 1320) # PCIe Base Specs Config Headers
    gds.add_box(21, 0, 760, 1050, 1310, 1320) # BAR0 & MSI-X Capabilities

    # 5. Core Standard Cell Rows
    for row in range(55):
        y = 180 + row * 21
        gds.add_box(21, 1, 180, y, 1320, y + 8)

    # 6. Power Grid
    for sx in range(14):
        x = 210 + sx * 80
        gds.add_box(31, 0, x, 170, x + 6, 1340)
    for sy in range(14):
        y = 210 + sy * 80
        gds.add_box(41, 0, 170, y, 1340, y + 6)

    # 7. Symmetrical H-Tree Clock Trunk (Metal 4)
    gds.add_box(51, 1, 740, 180, 760, 1330)
    gds.add_box(51, 1, 180, 740, 1320, 760)

    gds.end_str()
    gds.close()

    print(f"[OK] Generated GDSII: {gds_path} ({os.path.getsize(gds_path)} bytes)")

if __name__ == "__main__":
    generate_pcie_layout()
