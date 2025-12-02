REF_SRC := $(abspath ../../../../../libs/datapath/rtl/muladdsub.v)
TB := $(abspath tb_muladdsub_parity.sv)
CPP := $(abspath verilator_muladdsub_parity.cpp)
COMPARE := $(abspath ../compare_traces.py)
TOP := tb_muladdsub_parity
BUILD := build

.PHONY: verilator xsim compare clean

verilator:
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal +define+VERILATE \
		--top-module muladdsub --Mdir $(BUILD)/verilator \
		$(REF_SRC) $(CPP)
	$(MAKE) -C $(BUILD)/verilator -f Vmuladdsub.mk Vmuladdsub
	$(BUILD)/verilator/Vmuladdsub +TRACE=$(abspath $(BUILD))/verilator/trace.csv

xsim:
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -work work -d HIGGS_FPGA_XILINX \
		$(REF_SRC) $(TB)
	cd $(BUILD)/xsim && xelab -debug typical -s $(TOP) work.$(TOP)
	cd $(BUILD)/xsim && xsim $(TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 $(COMPARE) $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
