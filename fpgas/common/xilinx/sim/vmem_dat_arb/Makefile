ARB := $(abspath ../../../../../libs/spinal/hw/gen/VmemDatArbOut1_1.v)
WRAPPER := $(abspath vmem_dat_arb_test_top.sv)
TB := $(abspath tb_vmem_dat_arb_parity.sv)
CPP := $(abspath verilator_vmem_dat_arb_parity.cpp)
COMPARE := $(abspath ../compare_traces.py)
TOP := vmem_dat_arb_test_top
TB_TOP := tb_vmem_dat_arb_parity
BUILD := build

.PHONY: generate verilator xsim compare clean

generate:
	$(MAKE) -C ../../../../../libs/spinal vao

verilator: generate
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal --top-module $(TOP) \
		--Mdir $(BUILD)/verilator $(ARB) $(WRAPPER) $(CPP)
	$(MAKE) -C $(BUILD)/verilator -f V$(TOP).mk V$(TOP)
	$(BUILD)/verilator/V$(TOP) +TRACE=$(abspath $(BUILD))/verilator/trace.csv

xsim: generate
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -work work $(ARB) $(WRAPPER) $(TB)
	cd $(BUILD)/xsim && xelab -debug typical -s $(TB_TOP) work.$(TB_TOP)
	cd $(BUILD)/xsim && xsim $(TB_TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 $(COMPARE) $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
