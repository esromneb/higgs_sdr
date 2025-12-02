RTL := ../../scalar_memory_xilinx.sv
TB := tb_scalar_memory_xilinx.sv
TOP := tb_scalar_memory_xilinx
BUILD := build

.PHONY: verilator xsim compare clean

verilator:
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal -DNO_SCALAR_MIF \
		--top-module scalar_memory --Mdir $(BUILD)/verilator $(RTL) ../../verilator_scalar_memory_xilinx.cpp
	$(MAKE) -C $(BUILD)/verilator -f Vscalar_memory.mk Vscalar_memory
	$(BUILD)/verilator/Vscalar_memory +TRACE=$(BUILD)/verilator/trace.csv

xsim:
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -d NO_SCALAR_MIF -work work ../../../../scalar_memory_xilinx.sv ../../$(TB)
	cd $(BUILD)/xsim && xelab -debug typical -s $(TOP) work.$(TOP)
	cd $(BUILD)/xsim && xsim $(TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	cmp $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
