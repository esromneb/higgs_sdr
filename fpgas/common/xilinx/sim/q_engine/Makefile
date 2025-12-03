REPO_ROOT := $(abspath ../../../../..)
HERE := $(abspath .)
BUILD := $(HERE)/build
XSIM_BUILD := $(BUILD)/xsim
VERILATOR_BUILD := $(BUILD)/verilator
QENGINE := $(REPO_ROOT)/libs/q-engine
IP := $(REPO_ROOT)/libs/ip-library
RISCV := $(REPO_ROOT)/libs/riscv-baseband
DATAPATH := $(REPO_ROOT)/libs/datapath
SPINAL := $(REPO_ROOT)/libs/spinal
XILINX := $(REPO_ROOT)/fpgas/common/xilinx
MODULES := $(REPO_ROOT)/fpgas/common/modules
COMPARE := $(XILINX)/sim/compare_traces.py
RISCV_GCC := /opt/riscv/bin/riscv32-unknown-elf-gcc
RISCV_OBJCOPY := /opt/riscv/bin/riscv32-unknown-elf-objcopy
RISCV_INC := $(RISCV)/c/inc
HEX2MIF := $(RISCV)/scripts/hex2mif.py

PISTON_SOURCES := \
	$(QENGINE)/piston/hdl/k15_op.v \
	$(QENGINE)/piston/hdl/round_sat_dat_1_1.v \
	$(QENGINE)/piston/hdl/bs_dat_2_1.v \
	$(QENGINE)/piston/hdl/cfg_ctrl.v \
	$(QENGINE)/piston/hdl/cfg_dat.v \
	$(QENGINE)/piston/hdl/defunnel_ctrl_3_1.v \
	$(QENGINE)/piston/hdl/defunnel_dat_3_1.v \
	$(QENGINE)/piston/hdl/eb15_ctrl.v \
	$(QENGINE)/piston/hdl/eb17_ctrl.v \
	$(QENGINE)/piston/hdl/eb_fifo_ctrl.v \
	$(QENGINE)/piston/hdl/funnel_ctrl_2_2.v \
	$(QENGINE)/piston/hdl/funnel_dat_2_2.v \
	$(QENGINE)/piston/hdl/p_decode_dat_1_2.v \
	$(QENGINE)/piston/hdl/p_decode_ctrl_1_2.v \
	$(QENGINE)/piston/hdl/ka_decode_dat_1_3.v \
	$(QENGINE)/piston/hdl/ka_decode_ctrl_1_3.v \
	$(QENGINE)/piston/hdl/perm_full_addr_dat_1_1.v \
	$(QENGINE)/piston/hdl/perm_full_data_dat_2_1.v \
	$(QENGINE)/piston/hdl/perm_addr_dat_1_1.v \
	$(QENGINE)/piston/hdl/perm_addr_slice.v \
	$(QENGINE)/piston/hdl/perm_data_dat_2_1.v \
	$(QENGINE)/piston/hdl/perm_data_slice.v \
	$(QENGINE)/piston/hdl/inmux_ctrl_4_1.v \
	$(QENGINE)/piston/hdl/inmux_dat_4_1.v \
	$(QENGINE)/piston/hdl/iperm_ctrl_2_1.v \
	$(QENGINE)/piston/hdl/iperm_dat_2_1.v \
	$(QENGINE)/piston/hdl/kap_ctrl_ctrl_1_5.v \
	$(QENGINE)/piston/hdl/kap_ctrl_dat_1_5.v \
	$(QENGINE)/piston/hdl/operm_ctrl_2_1.v \
	$(QENGINE)/piston/hdl/operm_dat_2_1.v \
	$(QENGINE)/piston/hdl/oumux_ctrl_2_5.v \
	$(QENGINE)/piston/hdl/oumux_dat_2_5.v \
	$(QENGINE)/piston/hdl/permutator_slice.v \
	$(QENGINE)/piston/hdl/piston.v \
	$(QENGINE)/piston/hdl/vector_ctrl_17_2.v \
	$(QENGINE)/piston/hdl/vector_dat_17_2.v \
	$(QENGINE)/piston/hdl/vector_slice.v \
	$(QENGINE)/piston/hdl/vmem_ctrl_6_5.v \
	$(QENGINE)/piston/hdl/vmem_dat_6_5_1_1.v \
	$(QENGINE)/piston/hdl/vmem_dat_arb_out_spinal_wrapper.v \
	$(SPINAL)/hw/gen/VmemDatArbOut1_1.v \
	$(REPO_ROOT)/libs/d-engine/rtl/elastic-buffer/eb15.sv \
	$(XILINX)/memory_slice_1_1_xilinx.sv

QENGINE_SOURCES := \
	$(RISCV)/hdl/generated/XbbRiscv.v \
	$(XILINX)/scalar_memory_xilinx.sv \
	$(QENGINE)/hdl/slicer.v \
	$(QENGINE)/hdl/dma/dma_in.v \
	$(QENGINE)/hdl/dma/dma_out.v \
	$(QENGINE)/hdl/dma/dma_in_dummy.v \
	$(QENGINE)/hdl/nco/nco_gen.v \
	$(BUILD)/patched/nco.v \
	$(QENGINE)/hdl/q_engine.v \
	$(QENGINE)/hdl/ring_bus/ring_bus.v \
	$(IP)/fwft_fifos/sc_fifo/hdl/fwft_sc_fifo.v \
	$(IP)/fwft_fifos/sc_fifo/hdl/generic_dpram.v \
	$(BUILD)/patched/generic_fifo_sc_a.v \
	$(BUILD)/patched/muladdsub.v \
	$(MODULES)/demapper/demapper.sv

DEFINES := -d HIGGS_FPGA_XILINX -d MEMORY_SLICE_1_1 -d VMEM_DAT_ARB_OUT_1_1
VERILATOR_DEFINES := -DHIGGS_FPGA_XILINX -DMEMORY_SLICE_1_1 -DVMEM_DAT_ARB_OUT_1_1
MIFS := scalar0.mif scalar1.mif scalar2.mif scalar3.mif

all: compare

firmware: $(BUILD)/firmware/scalar0.mif

$(BUILD)/firmware/scalar0.mif: riscv_prog/src/main.c
	mkdir -p $(BUILD)/firmware
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -O2 -c -I$(RISCV_INC) \
		-o $(BUILD)/firmware/main.o $<
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -c -I$(RISCV_INC) \
		-D__ASSEMBLY__=1 -o $(BUILD)/firmware/crt.o $(RISCV_INC)/crt_standard.S
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -e_start \
		-T $(RISCV_INC)/ld_standard -o $(BUILD)/firmware/main.elf \
		$(BUILD)/firmware/crt.o $(BUILD)/firmware/main.o
	$(RISCV_OBJCOPY) -O ihex $(BUILD)/firmware/main.elf $(BUILD)/firmware/main.hex
	python3 $(HEX2MIF) -i $(BUILD)/firmware/main.hex \
		-o0 $(BUILD)/firmware/scalar0.mif -o1 $(BUILD)/firmware/scalar1.mif \
		-o2 $(BUILD)/firmware/scalar2.mif -o3 $(BUILD)/firmware/scalar3.mif

$(BUILD)/patched/nco.v: | $(BUILD)/patched
	python3 -c "src=open('$(QENGINE)/hdl/nco/nco.v').read(); src=src.replace(');\n// per edge', ');\nwire [8:0] node1_addr; // build-only declaration hoist\n// per edge', 1); src=src.replace('wire [8:0] node1_addr;\n', '', 1); open('$@','w').write(src)"

$(BUILD)/patched/generic_fifo_sc_a.v: | $(BUILD)/patched
	sed -e '/^   reg                    full_r;$$/d' \
	    -e '/^   reg                    empty_r;$$/d' \
	    -e '/^   wire                   full_n, empty_n;$$/d' \
	    -e '/^   reg                    full_n_r, empty_n_r;$$/d' \
	    -e '/^`timescale 1ns \/ 100ps$$/d' \
	    $(IP)/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v > $@

$(BUILD)/patched/muladdsub.v: | $(BUILD)/patched
	sed -e '/^`timescale 1 ns \/ 1 ps$$/d' $(DATAPATH)/rtl/muladdsub.v > $@

$(BUILD)/patched:
	mkdir -p $@

prepare: firmware $(BUILD)/patched/nco.v $(BUILD)/patched/generic_fifo_sc_a.v $(BUILD)/patched/muladdsub.v
	mkdir -p $(XSIM_BUILD) $(VERILATOR_BUILD)
	cp $(BUILD)/firmware/scalar[0-3].mif $(XSIM_BUILD)/
	cp $(BUILD)/firmware/scalar[0-3].mif $(VERILATOR_BUILD)/

xsim: prepare
	cd $(XSIM_BUILD) && xvlog -sv -work work $(DEFINES) \
		$(PISTON_SOURCES) $(QENGINE_SOURCES) \
		$(HERE)/q_engine_test_top.sv $(HERE)/tb_q_engine_parity.sv
	cd $(XSIM_BUILD) && xelab -L xpm -timescale 1ns/1ps -debug typical \
		-s q_engine_snapshot work.tb_q_engine_parity
	cd $(XSIM_BUILD) && xsim q_engine_snapshot -R --testplusarg TRACE=trace.csv \
		| tee xsim.log
	grep -q "PASS: q_engine firmware DMA loopback" $(XSIM_BUILD)/xsim.log

verilator: prepare
	verilator --cc --exe --top-module q_engine_test_top \
		-Wno-fatal -Wno-WIDTH -Wno-PINMISSING -Wno-CASEINCOMPLETE \
		$(VERILATOR_DEFINES) \
		$(PISTON_SOURCES) $(QENGINE_SOURCES) \
		$(XILINX)/sim/memory_slice/xpm_memory_tdpram_verilator_model.sv \
		$(HERE)/q_engine_test_top.sv $(HERE)/tb_q_engine_verilator.cpp \
		-Mdir $(VERILATOR_BUILD)/obj
	$(MAKE) -C $(VERILATOR_BUILD)/obj -f Vq_engine_test_top.mk Vq_engine_test_top
	cd $(VERILATOR_BUILD) && ./obj/Vq_engine_test_top trace.csv

compare: xsim verilator
	python3 $(COMPARE) $(XSIM_BUILD)/trace.csv $(VERILATOR_BUILD)/trace.csv
	@echo "PASS: q_engine XSIM and Verilator cycle traces match"

clean:
	rm -rf $(BUILD)

.PHONY: all firmware prepare xsim verilator compare clean
