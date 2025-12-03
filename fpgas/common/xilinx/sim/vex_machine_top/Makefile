# vex_machine_top integration smoke-test harness.
#
# Unlike the other harnesses in this directory (each of which cross-checks
# a single leaf module against a dual/independent implementation), this
# harness assembles the *entire* real design reachable from
# fpgas/common/modules/vex_machine_top.v -- VexRiscv core, q_engine bus/CSR
# decode, GPIO, and every piston/DMA/ring_bus/NCO leaf already verified
# individually elsewhere in this directory -- and runs one real, compiled
# RISC-V program (riscv_prog/) through it under both Verilator and XSIM.
# See README.md for full rationale and scope.

ROOT := $(abspath ../../../../..)
Q_ENGINE := $(ROOT)/libs/q-engine
IP_LIBRARY := $(ROOT)/libs/ip-library
RISCV_BASEBAND := $(ROOT)/libs/riscv-baseband
DATAPATH := $(ROOT)/libs/datapath
MODULES := $(ROOT)/fpgas/common/modules

VMT := $(MODULES)/vex_machine_top.v
BUILD := build
GEN := $(abspath $(BUILD))/gen

# Mirrors libs/q-engine/scripts/make_include/verilog_paths.mk's
# Q_ENGINE_ALL_VERILOG, plus demapper.sv (instantiated by q_engine.v but
# not tracked in that list) and vex_machine_top.v itself (one level above
# q_engine). alu54b_wrapper.v is intentionally excluded: it is not
# instantiated anywhere in this reachable set (only muladdsub.v is, and it
# does not use alu54b_wrapper).
SOURCES := \
	$(VMT) \
	$(RISCV_BASEBAND)/hdl/generated/XbbRiscv.v \
	$(Q_ENGINE)/piston/hdl/k15_op.v \
	$(Q_ENGINE)/piston/hdl/round_sat_dat_1_1.v \
	$(Q_ENGINE)/piston/hdl/bs_dat_2_1.v \
	$(Q_ENGINE)/piston/hdl/cfg_ctrl.v \
	$(Q_ENGINE)/piston/hdl/cfg_dat.v \
	$(Q_ENGINE)/piston/hdl/defunnel_ctrl_3_1.v \
	$(Q_ENGINE)/piston/hdl/defunnel_dat_3_1.v \
	$(Q_ENGINE)/piston/hdl/eb15_ctrl.v \
	$(Q_ENGINE)/piston/hdl/eb17_ctrl.v \
	$(Q_ENGINE)/piston/hdl/eb_fifo_ctrl.v \
	$(Q_ENGINE)/piston/hdl/funnel_ctrl_2_2.v \
	$(Q_ENGINE)/piston/hdl/funnel_dat_2_2.v \
	$(Q_ENGINE)/piston/hdl/p_decode_dat_1_2.v \
	$(Q_ENGINE)/piston/hdl/p_decode_ctrl_1_2.v \
	$(Q_ENGINE)/piston/hdl/ka_decode_dat_1_3.v \
	$(Q_ENGINE)/piston/hdl/ka_decode_ctrl_1_3.v \
	$(Q_ENGINE)/piston/hdl/perm_full_addr_dat_1_1.v \
	$(Q_ENGINE)/piston/hdl/perm_full_data_dat_2_1.v \
	$(Q_ENGINE)/piston/hdl/perm_addr_dat_1_1.v \
	$(Q_ENGINE)/piston/hdl/perm_addr_slice.v \
	$(Q_ENGINE)/piston/hdl/perm_data_dat_2_1.v \
	$(Q_ENGINE)/piston/hdl/perm_data_slice.v \
	$(Q_ENGINE)/piston/hdl/inmux_ctrl_4_1.v \
	$(Q_ENGINE)/piston/hdl/inmux_dat_4_1.v \
	$(Q_ENGINE)/piston/hdl/iperm_ctrl_2_1.v \
	$(Q_ENGINE)/piston/hdl/iperm_dat_2_1.v \
	$(Q_ENGINE)/piston/hdl/kap_ctrl_ctrl_1_5.v \
	$(Q_ENGINE)/piston/hdl/kap_ctrl_dat_1_5.v \
	$(Q_ENGINE)/piston/hdl/operm_ctrl_2_1.v \
	$(Q_ENGINE)/piston/hdl/operm_dat_2_1.v \
	$(Q_ENGINE)/piston/hdl/oumux_ctrl_2_5.v \
	$(Q_ENGINE)/piston/hdl/oumux_dat_2_5.v \
	$(Q_ENGINE)/piston/hdl/permutator_slice.v \
	$(Q_ENGINE)/piston/hdl/piston.v \
	$(Q_ENGINE)/piston/hdl/vector_ctrl_17_2.v \
	$(Q_ENGINE)/piston/hdl/vector_dat_17_2.v \
	$(Q_ENGINE)/piston/hdl/vector_slice.v \
	$(Q_ENGINE)/piston/hdl/vmem_ctrl_6_5.v \
	$(Q_ENGINE)/piston/hdl/vmem_dat_6_5_1_1.v \
	$(Q_ENGINE)/piston/hdl/vmem_dat_arb_out_spinal_wrapper.v \
	$(ROOT)/libs/spinal/hw/gen/VmemDatArbOut1_1.v \
	$(ROOT)/libs/d-engine/rtl/elastic-buffer/eb15.sv \
	$(ROOT)/fpgas/common/xilinx/memory_slice_1_1_xilinx.sv \
	$(ROOT)/fpgas/common/xilinx/scalar_memory_xilinx.sv \
	$(Q_ENGINE)/hdl/slicer.v \
	$(Q_ENGINE)/hdl/dma/dma_in.v \
	$(Q_ENGINE)/hdl/dma/dma_out.v \
	$(Q_ENGINE)/hdl/dma/dma_in_dummy.v \
	$(Q_ENGINE)/hdl/nco/nco_gen.v \
	$(GEN)/nco.v \
	$(Q_ENGINE)/hdl/q_engine.v \
	$(Q_ENGINE)/hdl/ring_bus/ring_bus.v \
	$(IP_LIBRARY)/fwft_fifos/sc_fifo/hdl/fwft_sc_fifo.v \
	$(IP_LIBRARY)/fwft_fifos/sc_fifo/hdl/generic_dpram.v \
	$(GEN)/generic_fifo_sc_a.v \
	$(GEN)/muladdsub.v \
	$(MODULES)/demapper/demapper.sv

TB := $(abspath tb_vex_machine_top_parity.sv)
CPP := $(abspath verilator_vex_machine_top_parity.cpp)
COMPARE := $(abspath ../compare_traces.py)
TOP := tb_vex_machine_top_parity

RISCV_GCC := /opt/riscv/bin/riscv32-unknown-elf-gcc
RISCV_OBJCOPY := /opt/riscv/bin/riscv32-unknown-elf-objcopy
RISCV_C_INC := $(RISCV_BASEBAND)/c/inc
HEX2MIF := $(RISCV_BASEBAND)/scripts/hex2mif.py

.PHONY: gen riscv_prog vmem_stubs verilator xsim compare clean

# Compile the real riscv_prog/src/main.c GPIO smoke-test program with the
# same crt0/linker-script infrastructure used by the (never-completed)
# libs/riscv-baseband/Makefile "mif_style" flow, then convert its Intel-hex
# output into the 4 byte-lane .mif files scalar_memory.v's $readmemh
# expects (see README.md).
riscv_prog: $(GEN)/scalar0.mif

$(GEN)/scalar0.mif: riscv_prog/src/main.c
	mkdir -p $(GEN)
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -O2 -c -I$(RISCV_C_INC) \
		-o $(GEN)/riscv_prog_main.o riscv_prog/src/main.c
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -c -I$(RISCV_C_INC) \
		-D__ASSEMBLY__=1 -o $(GEN)/riscv_prog_crt.o $(RISCV_C_INC)/crt_standard.S
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -e_start \
		-T $(RISCV_C_INC)/ld_standard \
		-o $(GEN)/riscv_prog.elf $(GEN)/riscv_prog_crt.o $(GEN)/riscv_prog_main.o
	$(RISCV_OBJCOPY) -O ihex $(GEN)/riscv_prog.elf $(GEN)/riscv_prog.hex
	python3 $(HEX2MIF) -i $(GEN)/riscv_prog.hex \
		-o0 $(GEN)/scalar0.mif -o1 $(GEN)/scalar1.mif \
		-o2 $(GEN)/scalar2.mif -o3 $(GEN)/scalar3.mif

# q_engine's 32 vector-memory (piston) instances each unconditionally
# $readmemh a "vmemN.mif" file at time 0 regardless of whether the running
# program performs any vector ops (it doesn't -- see riscv_prog/src/main.c
# and README.md's "Scope" section). vex_machine_top.v only exposes
# override parameters for VMEM0-15; VMEM16-31 always resolve to q_engine's
# own literal defaults ("vmem16.mif".."vmem31.mif"). Rather than pass 32
# path parameters, every VMEM/SCALAR_MEM parameter is left at its default
# and the expected filenames are simply generated in each build
# directory's current working directory before running that simulator.
vmem_stubs:
	mkdir -p $(GEN)
	for n in $$(seq 0 31); do printf '@0\n00\n' > $(GEN)/vmem$$n.mif; done

gen: riscv_prog vmem_stubs nco_patch fifo_patch muladdsub_patch

# generic_fifo_sc_a.v (as already documented in
# ../generic_fifo_sc_a/README.md and NOTES.md) re-declares several signals
# that are already declared by its own ANSI-style output port list --
# redundant but harmless duplicate declarations that Verilator/Vivado's
# synthesizer tolerate as a warning, but that XSIM's `xvlog` frontend
# rejects as a hard error. Reuses the exact same duplicate-declaration
# build-only patch as that harness (no behavioral effect; never touches
# the committed source).
#
# generic_fifo_sc_a.v is also the *only* file in this whole harness's
# source list that declares its own `` `timescale ``; XSIM's `xelab`
# (unlike Verilator, and unlike the small 2-file generic_fifo_sc_a/
# harness) treats mixing a timescale-having module with dozens of
# timescale-lacking ones as a hard elaboration error. generic_fifo_sc_a.v
# has no `#`-delay statements (confirmed by inspection), so its timescale
# directive has no effect on simulated behavior; this build-only copy
# simply drops it so every module in the design implicitly shares the
# same (tool-default) time unit, rather than patching timescale directives
# into every other file. tb_vex_machine_top_parity.sv declares its own
# explicit `` `timescale `` for its `#5 clk=~clk` generator, so this has no
# effect on the testbench's own timing either.
fifo_patch:
	mkdir -p $(GEN)
	sed -e '/^   reg                    full_r;$$/d' \
	    -e '/^   reg                    empty_r;$$/d' \
	    -e '/^   wire                   full_n, empty_n;$$/d' \
	    -e '/^   reg                    full_n_r, empty_n_r;$$/d' \
	    -e '/^`timescale 1ns \/ 100ps$$/d' \
	    $(IP_LIBRARY)/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v > $(GEN)/generic_fifo_sc_a.v

# muladdsub.v also declares its own `` `timescale `` (unlike almost every
# other file reachable from vex_machine_top); for the same reason as
# generic_fifo_sc_a.v above (XSIM's all-or-nothing timescale rule, no
# `#`-delay statements inside), this build-only copy drops it.
muladdsub_patch:
	mkdir -p $(GEN)
	sed -e '/^`timescale 1 ns \/ 1 ps$$/d' \
	    $(DATAPATH)/rtl/muladdsub.v > $(GEN)/muladdsub.v

# nco.v (per libs/q-engine/hdl/nco/nco.v) is code-generator output whose
# combinational LUT block for node1 uses `node1_addr` several hundred
# lines before that wire's own declaration -- legal, tolerated Verilog-2001
# implicit-net usage that both Verilator and (for CS12's actual real
# hardware sign-off flow) Vivado's synthesizer accept, but that XSIM's
# `xvlog` frontend rejects as a hard "used before its declaration" error
# (VRFC 10-3380), in both -sv and plain-Verilog modes. This build-only,
# generated copy hoists a single forward declaration of `node1_addr` to
# just after the port list and deletes the now-redundant original
# declaration later in the file (leaving the original `assign` untouched);
# no behavioral effect. The committed legacy source is never modified. See
# README.md.
nco_patch:
	mkdir -p $(GEN)
	python3 -c "\
import re; \
src = open('$(Q_ENGINE)/hdl/nco/nco.v').read(); \
src = src.replace(');\n// per edge', ');\nwire [8:0] node1_addr; // build-only hoist, see NOTES.md\n// per edge', 1); \
src = src.replace('wire [8:0] node1_addr;\n', '', 1); \
open('$(GEN)/nco.v', 'w').write(src)"

verilator: gen
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal -Wno-PINMISSING -Wno-WIDTH -Wno-UNOPTFLAT \
		+define+VERILATE +define+HIGGS_FPGA_XILINX \
		+define+MEMORY_SLICE_1_1 +define+VMEM_DAT_ARB_OUT_1_1 \
		--top-module vex_machine_top --Mdir $(BUILD)/verilator \
		$(ROOT)/fpgas/common/xilinx/sim/memory_slice/xpm_memory_tdpram_verilator_model.sv \
		$(SOURCES) $(CPP)
	$(MAKE) -C $(BUILD)/verilator -f Vvex_machine_top.mk Vvex_machine_top
	cp $(GEN)/scalar*.mif $(GEN)/vmem*.mif $(BUILD)/verilator/
	cd $(BUILD)/verilator && ./Vvex_machine_top +TRACE=$(abspath $(BUILD))/verilator/trace.csv

xsim: gen
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -work work -d HIGGS_FPGA_XILINX \
		-d MEMORY_SLICE_1_1 -d VMEM_DAT_ARB_OUT_1_1 \
		$(SOURCES) $(TB)
	cd $(BUILD)/xsim && xelab -L xpm -timescale 1ns/1ps -debug typical \
		-s $(TOP) work.$(TOP)
	cp $(GEN)/scalar*.mif $(GEN)/vmem*.mif $(BUILD)/xsim/
	cd $(BUILD)/xsim && xsim $(TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 $(COMPARE) $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
