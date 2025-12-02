REF_SRC := $(abspath ../../../../../libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_dpram.v)
TB := $(abspath tb_generic_dpram_parity.sv)
CPP := $(abspath verilator_generic_dpram_parity.cpp)
COMPARE := $(abspath ../compare_traces.py)
TOP := tb_generic_dpram_parity
BUILD := build

.PHONY: verilator xsim compare clean

verilator:
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal -Gaw=4 -Gdw=8 \
		--top-module generic_dpram --Mdir $(BUILD)/verilator \
		$(REF_SRC) $(CPP)
	$(MAKE) -C $(BUILD)/verilator -f Vgeneric_dpram.mk Vgeneric_dpram
	$(BUILD)/verilator/Vgeneric_dpram +TRACE=$(abspath $(BUILD))/verilator/trace.csv

xsim:
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -work work $(REF_SRC) $(TB)
	cd $(BUILD)/xsim && xelab -debug typical -s $(TOP) work.$(TOP)
	cd $(BUILD)/xsim && xsim $(TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 $(COMPARE) $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
