# CS12 HDL manifest

This is the source closure requested by
`fpgas/cs/cs12/build/sources.tcl` and its five sourced
`diamond_sources.tcl` files.  Paths are relative to the repository root.
Memory-initialization `.mif` files are listed separately because they are
build inputs, not HDL.  The generated `XbbRiscv.v` is self-contained RTL.

## CS12 and common HDL

```text
fpgas/cs/cs12/hdl/cs12_top.sv
fpgas/common/ip/lattice/sys_pll/sys_pll.v
fpgas/common/modules/core_top.sv
fpgas/common/modules/core_reset.sv
fpgas/common/modules/mib_cdc.sv
fpgas/common/modules/piper.sv
fpgas/common/modules/vex_machine_top.v
```

## Command, MIB, and FIFO HDL

```text
libs/ip-library/interfaces/cmd_interface/hdl/intf_cmd.sv
libs/ip-library/interfaces/cmd_interface/hdl/cmd_master_example.sv
libs/ip-library/interfaces/cmd_interface/hdl/cmd_slave_example.sv
libs/ip-library/mib_bus/hdl/mib_master.sv
libs/ip-library/mib_bus/hdl/mib_slave.sv
libs/ip-library/mib_bus/hdl/mib_master_wrapper.sv
libs/ip-library/mib_bus/hdl/mib_slave_wrapper.sv
libs/ip-library/lattice_support/fifos/pmi_fifo_sc_fwft_v1_0/hdl/pmi_fifo_sc_fwft_v1_0.sv
libs/ip-library/lattice_support/fifos/pmi_fifo_dc_fwft_v1_0/hdl/pmi_fifo_dc_fwft_v1_0.sv
libs/ip-library/fwft_fifos/sc_fifo/hdl/fwft_sc_fifo.v
libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_dpram.v
libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v
```

## Q-engine HDL

```text
libs/q-engine/hdl/scalar_memory.v
libs/q-engine/hdl/dma/dma_in.v
libs/q-engine/hdl/dma/dma_in_dummy.v
libs/q-engine/hdl/ring_bus/ring_bus.v
libs/q-engine/hdl/nco/nco.v
libs/q-engine/hdl/nco/nco_gen.v
libs/q-engine/hdl/dma/dma_out.v
libs/q-engine/hdl/q_engine.v
fpgas/common/modules/demapper/demapper.sv
libs/q-engine/hdl/slicer.v
libs/q-engine/piston/hdl/k15_op.v
libs/q-engine/piston/hdl/round_sat_dat_1_1.v
libs/q-engine/piston/hdl/eb15_ctrl.v
libs/q-engine/piston/hdl/eb17_ctrl.v
libs/q-engine/piston/hdl/eb_fifo_ctrl.v
libs/q-engine/piston/hdl/memory_slice.v
libs/q-engine/piston/hdl/permutator_slice.v
libs/q-engine/piston/hdl/iperm_ctrl_2_1.v
libs/q-engine/piston/hdl/iperm_dat_2_1.v
libs/q-engine/piston/hdl/operm_ctrl_2_1.v
libs/q-engine/piston/hdl/operm_dat_2_1.v
libs/q-engine/piston/hdl/kap_ctrl_ctrl_1_5.v
libs/q-engine/piston/hdl/kap_ctrl_dat_1_5.v
libs/q-engine/piston/hdl/piston.v
libs/q-engine/piston/hdl/vector_slice.v
libs/q-engine/piston/hdl/vector_dat_17_2.v
libs/q-engine/piston/hdl/inmux_dat_4_1.v
libs/q-engine/piston/hdl/oumux_dat_2_5.v
libs/q-engine/piston/hdl/funnel_dat_2_2.v
libs/q-engine/piston/hdl/defunnel_dat_3_1.v
libs/q-engine/piston/hdl/bs_dat_2_1.v
libs/q-engine/piston/hdl/vector_ctrl_17_2.v
libs/q-engine/piston/hdl/inmux_ctrl_4_1.v
libs/q-engine/piston/hdl/oumux_ctrl_2_5.v
libs/q-engine/piston/hdl/defunnel_ctrl_3_1.v
libs/q-engine/piston/hdl/funnel_ctrl_2_2.v
libs/q-engine/piston/hdl/vmem_ctrl_6_5.v
libs/q-engine/piston/hdl/vmem_dat_6_5.v
libs/q-engine/piston/hdl/cfg_ctrl.v
libs/q-engine/piston/hdl/cfg_dat.v
libs/q-engine/piston/hdl/ka_decode_dat_1_3.v
libs/q-engine/piston/hdl/ka_decode_ctrl_1_3.v
libs/q-engine/piston/hdl/p_decode_dat_1_2.v
libs/q-engine/piston/hdl/p_decode_ctrl_1_2.v
libs/q-engine/piston/hdl/perm_full_addr_dat_1_1.v
libs/q-engine/piston/hdl/perm_full_data_dat_2_1.v
libs/q-engine/piston/hdl/perm_addr_dat_1_1.v
libs/q-engine/piston/hdl/perm_addr_slice.v
libs/q-engine/piston/hdl/perm_data_dat_2_1.v
libs/q-engine/piston/hdl/perm_data_slice.v
```

## VexRiscv and datapath HDL

```text
libs/riscv-baseband/hdl/generated/XbbRiscv.v
libs/datapath/rtl/alu54b_wrapper.v
libs/datapath/rtl/muladdsub.v
```

## Non-HDL build inputs

```text
libs/q-engine/verilate/scalar0.mif
libs/q-engine/verilate/scalar1.mif
libs/q-engine/verilate/scalar2.mif
libs/q-engine/verilate/scalar3.mif
fpgas/packages/udp_cmd_pkg.sv
libs/ip-library/lattice_support/gbit_mac/packages/udp_cmd_pkg.sv
```

`udp_cmd_pkg.sv` is included by `cs12_top.sv`; the package include directories
are therefore also mandatory.  The direct closure may grow when replacing
Lattice IP with Xilinx-specific wrappers; additions must be recorded here.

## CS12 Vivado replacement overlay

`fpgas/cs/cs12/build/vivado/build.tcl` excludes the Lattice source named in
the left column and adds the corresponding Xilinx implementation in the right
column:

| Replaced source/primitive | Xilinx implementation | Selection | Consumers | Verification |
| --- | --- | --- | --- | --- |
| `fpgas/common/ip/lattice/sys_pll/sys_pll.v` | `fpgas/cs/cs12/build/vivado/hdl/sys_pll.sv` | Excluded/added by `build.tcl` | CS12 `core_top` | Synthesized and routed; hardware pending |
| `fpgas/common/modules/core_top.sv` | `fpgas/cs/cs12/build/vivado/hdl/core_top.sv` | Excluded/added by `build.tcl` | `cs12_top` | Synthesized and routed; hardware pending |
| Lattice `pmi_fifo_dc` macro | `fpgas/cs/cs12/build/vivado/hdl/pmi_fifo_dc.sv` | Vivado source overlay | `mib_cdc` | Synthesized and routed; simulation path is bypassed under `VERILATE` |
| `libs/q-engine/hdl/scalar_memory.v` | `fpgas/common/xilinx/scalar_memory_xilinx.sv` | Excluded/added by `build.tcl` | `q_engine` | Directed/fuzz XSIM and Verilator evidence; synthesized and routed |
| `libs/q-engine/piston/hdl/memory_slice.v`, via legacy `vmem_dat_6_5.v` | `fpgas/common/xilinx/memory_slice_1_1_xilinx.sv` | Parent replacement below | `vmem_dat_6_5_1_1` | Tagged dual-port XSIM contract test; synthesized and routed |
| `libs/q-engine/piston/hdl/vmem_dat_6_5.v` | `libs/q-engine/piston/hdl/vmem_dat_6_5_1_1.v`, `vmem_dat_arb_out_spinal_wrapper.v`, generated `libs/spinal/hw/gen/VmemDatArbOut1_1.v`, and `fpgas/common/xilinx/memory_slice_1_1_xilinx.sv` | Legacy parent excluded by `build.tcl`; `piston.v` selects the replacement under `HIGGS_FPGA_XILINX` | `piston`/Q-engine DMA and vector paths | Arbiter XSIM/Verilator trace parity; full parent 512-read XSIM scoreboard; synthesized and routed |

The datapath manifest additionally includes
`libs/datapath/rtl/alu54b_wrapper_xilinx.sv`; it is selected by
`HIGGS_FPGA_XILINX` inside its wrapper.  The replacement overlay is sufficient
for the committed routed checkpoint, not for board programming.
