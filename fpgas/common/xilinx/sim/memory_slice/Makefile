REF_SRC := ../../../../../libs/q-engine/piston/hdl/memory_slice.v
XIL_SRC := ../../memory_slice_xilinx.v
WRAPPER := memory_slice_dual_top.sv
TB := tb_memory_slice_parity.sv
TOP := tb_memory_slice_parity
BUILD := build
GEN := $(BUILD)/gen

# Real vendor XPM behavioral model, located relative to the installed xvlog.
XPM_MEMORY_SV := $(shell d=$$(command -v xvlog 2>/dev/null); \
	if [ -n "$$d" ]; then echo "$$(dirname $$(dirname $$d))/../data/ip/xpm/xpm_memory/hdl/xpm_memory.sv"; fi)

.PHONY: gen verilator xsim compare clean

gen:
	mkdir -p $(GEN)
	sed -e 's/module memory_slice /module memory_slice_ref /' \
	    -e 's/\bdpram\b/dpram_ref/g' \
	    $(REF_SRC) > $(GEN)/memory_slice_ref.v
	sed -e 's/module memory_slice /module memory_slice_xil /' \
	    -e 's/\bdpram\b/dpram_xil/g' \
	    $(XIL_SRC) > $(GEN)/memory_slice_xil.v

verilator: gen
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal \
		--top-module memory_slice_dual_top --Mdir $(BUILD)/verilator \
		$(GEN)/memory_slice_ref.v $(GEN)/memory_slice_xil.v \
		./xpm_memory_tdpram_verilator_model.sv ./$(WRAPPER) \
		../../verilator_memory_slice_parity.cpp
	$(MAKE) -C $(BUILD)/verilator -f Vmemory_slice_dual_top.mk Vmemory_slice_dual_top
	$(BUILD)/verilator/Vmemory_slice_dual_top +TRACE=$(BUILD)/verilator/trace.csv

xsim: gen
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	test -n "$(XPM_MEMORY_SV)" && test -f "$(XPM_MEMORY_SV)"
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -work work "$(XPM_MEMORY_SV)" \
		../gen/memory_slice_ref.v ../gen/memory_slice_xil.v \
		../../$(WRAPPER) ../../$(TB)
	cd $(BUILD)/xsim && xelab -debug typical -s $(TOP) work.$(TOP)
	cd $(BUILD)/xsim && xsim $(TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 compare_traces.py $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
