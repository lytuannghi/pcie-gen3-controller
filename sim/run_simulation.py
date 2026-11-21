#!/usr/bin/env python3
"""
Automated Simulation Script for PCIe Gen 3 (8 GT/s) Controller.
Compiles RTL and Testbench using Icarus Verilog and executes with vvp.
"""

import subprocess
import sys
import os

def run():
    repo_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(repo_dir)

    rtl_files = [
        "rtl/tl/pcie_tlp_gen.v",
        "rtl/tl/pcie_tlp_parse.v",
        "rtl/dll/pcie_dll_crc32.v",
        "rtl/dll/pcie_dll_seq.v",
        "rtl/phy/pcie_phy_ltssm.v",
        "rtl/phy/pcie_phy_scrambler.v",
        "rtl/phy/pcie_phy_pipe_if.v",
        "rtl/dma/pcie_axi4_dma_engine.v",
        "rtl/pcie_gen3_controller_top.v",
        "tb/tb_pcie_gen3.v"
    ]

    include_dirs = [
        "-Irtl/tl",
        "-Irtl/dll",
        "-Irtl/phy",
        "-Irtl/dma",
        "-Irtl"
    ]

    sim_bin = "sim/pcie_gen3_sim.vvp"
    os.makedirs("sim", exist_ok=True)

    cmd_compile = ["iverilog", "-g2005-sv"] + include_dirs + ["-o", sim_bin] + rtl_files
    print("[RUN] Compiling Verilog RTL with iverilog...")
    res = subprocess.run(cmd_compile, capture_output=True, text=True)
    if res.returncode != 0:
        print("[ERROR] Compilation failed:")
        print(res.stderr)
        sys.exit(1)
    print("[OK] Compilation successful.")

    print("[RUN] Running simulation with vvp...")
    res_run = subprocess.run(["vvp", sim_bin], capture_output=True, text=True)
    print(res_run.stdout)
    if res_run.stderr:
        print(res_run.stderr)

    if "[STATUS] PCIE GEN 3 CONTROLLER VERIFICATION: 100% PASSED" in res_run.stdout:
        print("[SUCCESS] All PCIe Gen 3 assertions verified!")
    else:
        print("[WARNING] Simulation did not return 100% PASS.")

if __name__ == "__main__":
    run()
