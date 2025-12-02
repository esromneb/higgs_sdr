REF_SRC := $(abspath ../../../../../libs/datapath/rtl/alu54b_wrapper.v)
XIL_SRC := $(abspath ../../../../../libs/datapath/rtl/alu54b_wrapper_xilinx.sv)
WRAPPER := $(abspath alu54b_dual_top.sv)
TB := $(abspath tb_alu54b_parity.sv)
CPP := $(abspath verilator_alu54b_parity.cpp)
COMPARE := $(abspath ../compare_traces.py)
TOP := tb_alu54b_parity
BUILD := build
GEN := $(BUILD)/gen

.PHONY: gen verilator xsim compare clean

gen:
	mkdir -p $(GEN)
	sed -e 's/module alu54b_wrapper$$/module alu54b_wrapper_ref/' \
	    -e 's/output wire \[54:0\] c,/output reg [54:0] c,/' \
	    $(REF_SRC) > $(GEN)/alu54b_wrapper_ref.v

verilator: gen
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal +define+VERILATE \
		--top-module alu54b_dual_top --Mdir $(BUILD)/verilator \
		$(abspath $(GEN))/alu54b_wrapper_ref.v $(XIL_SRC) $(WRAPPER) $(CPP)
	$(MAKE) -C $(BUILD)/verilator -f Valu54b_dual_top.mk Valu54b_dual_top
	$(BUILD)/verilator/Valu54b_dual_top +TRACE=$(abspath $(BUILD))/verilator/trace.csv

xsim: gen
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -work work -d VERILATE \
		$(abspath $(GEN))/alu54b_wrapper_ref.v $(XIL_SRC) $(WRAPPER) $(TB)
	cd $(BUILD)/xsim && xelab -debug typical -s $(TOP) work.$(TOP)
	cd $(BUILD)/xsim && xsim $(TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 $(COMPARE) $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
