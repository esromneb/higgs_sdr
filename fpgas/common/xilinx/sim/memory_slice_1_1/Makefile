DUT := $(abspath ../../memory_slice_1_1_xilinx.sv)
TB := $(abspath tb_memory_slice_1_1.sv)
TOP := tb_memory_slice_1_1
BUILD := build/xsim

.PHONY: xsim clean

xsim:
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)
	mkdir -p $(BUILD)
	cd $(BUILD) && xvlog -sv -work work $(DUT) $(TB)
	cd $(BUILD) && xelab -debug typical -L xpm -s $(TOP) work.$(TOP)
	cd $(BUILD) && xsim $(TOP) -R

clean:
	rm -rf build
