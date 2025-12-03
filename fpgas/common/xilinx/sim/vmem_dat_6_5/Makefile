ROOT := $(abspath ../../../../..)
PARENT := $(ROOT)/libs/q-engine/piston/hdl/vmem_dat_6_5_1_1.v
WRAPPER := $(ROOT)/libs/q-engine/piston/hdl/vmem_dat_arb_out_spinal_wrapper.v
ARB := $(ROOT)/libs/spinal/hw/gen/VmemDatArbOut1_1.v
MEMORY := $(ROOT)/fpgas/common/xilinx/memory_slice_1_1_xilinx.sv
EB := $(ROOT)/libs/d-engine/rtl/elastic-buffer/eb15.sv
TB := $(abspath tb_vmem_dat_6_5.sv)
TOP := tb_vmem_dat_6_5
BUILD := build/xsim

.PHONY: generate xsim clean

generate:
	$(MAKE) -C $(ROOT)/libs/spinal vao

xsim: generate
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)
	mkdir -p $(BUILD)
	cd $(BUILD) && xvlog -sv -d MEMORY_SLICE_1_1 -d VMEM_DAT_ARB_OUT_1_1 \
		-work work $(ARB) $(WRAPPER) $(MEMORY) $(EB) $(PARENT) $(TB)
	cd $(BUILD) && xelab -debug typical -L xpm -timescale 1ns/1ps \
		-s $(TOP) work.$(TOP)
	cd $(BUILD) && xsim $(TOP) -R

clean:
	rm -rf build
