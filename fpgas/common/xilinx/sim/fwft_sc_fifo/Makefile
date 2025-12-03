FIFO_SRC := $(abspath ../../../../../libs/ip-library/fwft_fifos/sc_fifo/hdl/fwft_sc_fifo.v)
GENERIC_FIFO_SRC := $(abspath ../../../../../libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v)
DPRAM_SRC := $(abspath ../../../../../libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_dpram.v)
TB := $(abspath tb_fwft_sc_fifo_parity.sv)
CPP := $(abspath verilator_fwft_sc_fifo_parity.cpp)
COMPARE := $(abspath ../compare_traces.py)
TOP := tb_fwft_sc_fifo_parity
BUILD := build
GEN := $(BUILD)/gen

.PHONY: gen verilator xsim compare clean

# XSIM rejects duplicate declarations in generic_fifo_sc_a.v. It also
# rejects designs where only some modules declare a timescale. Generate a
# behavior-identical build copy with the duplicates and lone timescale
# removed; the committed legacy source remains unchanged.
gen:
	mkdir -p $(GEN)
	sed -e '/^`timescale 1ns \/ 100ps$$/d' \
	    -e '/^   reg                    full_r;$$/d' \
	    -e '/^   reg                    empty_r;$$/d' \
	    -e '/^   wire                   full_n, empty_n;$$/d' \
	    -e '/^   reg                    full_n_r, empty_n_r;$$/d' \
	    $(GENERIC_FIFO_SRC) > $(GEN)/generic_fifo_sc_a.v

verilator: gen
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal -GDEPTH=16 -GWIDTH=8 -GALMOST_FULL=11 \
		--top-module fwft_sc_fifo --Mdir $(BUILD)/verilator \
		$(FIFO_SRC) $(abspath $(GEN))/generic_fifo_sc_a.v $(DPRAM_SRC) $(CPP)
	$(MAKE) -C $(BUILD)/verilator -f Vfwft_sc_fifo.mk Vfwft_sc_fifo
	$(BUILD)/verilator/Vfwft_sc_fifo +TRACE=$(abspath $(BUILD))/verilator/trace.csv

xsim: gen
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -work work $(DPRAM_SRC) \
		$(abspath $(GEN))/generic_fifo_sc_a.v $(FIFO_SRC) $(TB)
	cd $(BUILD)/xsim && xelab -debug typical -s $(TOP) work.$(TOP)
	cd $(BUILD)/xsim && xsim $(TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 $(COMPARE) $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
