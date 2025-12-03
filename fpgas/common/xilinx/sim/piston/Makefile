ROOT := $(abspath ../../../../..)
PISTON_DIR := $(ROOT)/libs/q-engine/piston/hdl
PISTON_RTL := $(filter-out $(PISTON_DIR)/memory_slice.v $(PISTON_DIR)/vmem_dat_6_5.v,$(wildcard $(PISTON_DIR)/*.v))
MULADDSUB := $(ROOT)/libs/datapath/rtl/muladdsub.v
EB := $(ROOT)/libs/d-engine/rtl/elastic-buffer/eb15.sv
ARB := $(ROOT)/libs/spinal/hw/gen/VmemDatArbOut1_1.v
MEMORY := $(ROOT)/fpgas/common/xilinx/memory_slice_1_1_xilinx.sv
XPM_MODEL := $(ROOT)/fpgas/common/xilinx/sim/memory_slice/xpm_memory_tdpram_verilator_model.sv
WRAPPER := $(abspath piston_test_top.sv)
TB := $(abspath tb_piston_parity.sv)
CPP := $(abspath verilator_piston_parity.cpp)
COMPARE := $(abspath ../compare_traces.py)
TOP := piston_test_top
TB_TOP := tb_piston_parity
BUILD := build

.PHONY: generate verilator xsim compare clean

generate:
	$(MAKE) -C $(ROOT)/libs/spinal vao

verilator: generate
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal --top-module $(TOP) \
		+define+HIGGS_FPGA_XILINX +define+MEMORY_SLICE_1_1 \
		+define+VMEM_DAT_ARB_OUT_1_1 --Mdir $(BUILD)/verilator \
		$(XPM_MODEL) $(MEMORY) $(EB) $(MULADDSUB) $(ARB) \
		$(PISTON_RTL) $(WRAPPER) $(CPP)
	$(MAKE) -C $(BUILD)/verilator -f V$(TOP).mk V$(TOP)
	$(BUILD)/verilator/V$(TOP) +TRACE=$(abspath $(BUILD))/verilator/trace.csv

xsim: generate
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -d HIGGS_FPGA_XILINX \
		-d MEMORY_SLICE_1_1 -d VMEM_DAT_ARB_OUT_1_1 -work work \
		$(MEMORY) $(EB) $(MULADDSUB) $(ARB) $(PISTON_RTL) $(WRAPPER) $(TB)
	cd $(BUILD)/xsim && xelab -debug typical -L xpm -timescale 1ns/1ps \
		-s $(TB_TOP) work.$(TB_TOP)
	cd $(BUILD)/xsim && xsim $(TB_TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 $(COMPARE) $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
