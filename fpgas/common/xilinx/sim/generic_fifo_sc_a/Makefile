REF_SRC := $(abspath ../../../../../libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v)
DPRAM_SRC := $(abspath ../../../../../libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_dpram.v)
TB := $(abspath tb_generic_fifo_sc_a_parity.sv)
CPP := $(abspath verilator_generic_fifo_sc_a_parity.cpp)
COMPARE := $(abspath ../compare_traces.py)
TOP := tb_generic_fifo_sc_a_parity
BUILD := build
GEN := $(BUILD)/gen

.PHONY: gen verilator xsim compare clean

# generic_fifo_sc_a.v's body re-declares several signals (full_r, empty_r,
# full_n, empty_n, full_n_r, empty_n_r) that are already declared by the
# module's own ANSI-style output port list -- redundant but harmless
# duplicate declarations that Vivado's synthesizer already tolerates as a
# warning (see doc/xilinx-port/NOTES.md), but that XSIM's `xvlog` frontend
# rejects as a hard error. This build-only, renamed copy strips exactly
# those duplicate declaration lines (no behavioral effect: the ANSI port
# declarations already establish the same types); the committed legacy
# source is never modified.
#
# generic_fifo_sc_a.v also declares its own `` `timescale ``, but
# generic_dpram.v does not; XSIM's `xvlog` (unlike Verilator) treats mixing
# timescale-having and timescale-lacking modules in one compilation as a
# hard error, so a build-only copy of generic_dpram.v with a matching
# timescale prepended is also generated here for XSIM's build only
# (Verilator does not need it).
gen:
	mkdir -p $(GEN)
	sed -e '/^   reg                    full_r;$$/d' \
	    -e '/^   reg                    empty_r;$$/d' \
	    -e '/^   wire                   full_n, empty_n;$$/d' \
	    -e '/^   reg                    full_n_r, empty_n_r;$$/d' \
	    $(REF_SRC) > $(GEN)/generic_fifo_sc_a.v
	{ echo '`timescale 1ns / 100ps'; cat $(DPRAM_SRC); } > $(GEN)/generic_dpram.v

verilator: gen
	rm -rf $(BUILD)/verilator
	mkdir -p $(BUILD)/verilator
	verilator -cc --exe -Wno-fatal -Gdw=8 -Gaw=4 -Gn=4 -GALMOST_FULL=5 \
		--top-module generic_fifo_sc_a --Mdir $(BUILD)/verilator \
		$(abspath $(GEN))/generic_fifo_sc_a.v $(DPRAM_SRC) $(CPP)
	$(MAKE) -C $(BUILD)/verilator -f Vgeneric_fifo_sc_a.mk Vgeneric_fifo_sc_a
	$(BUILD)/verilator/Vgeneric_fifo_sc_a +TRACE=$(abspath $(BUILD))/verilator/trace.csv

xsim: gen
	command -v xvlog >/dev/null
	command -v xelab >/dev/null
	command -v xsim >/dev/null
	rm -rf $(BUILD)/xsim
	mkdir -p $(BUILD)/xsim
	cd $(BUILD)/xsim && xvlog -sv -work work $(abspath $(GEN))/generic_dpram.v $(abspath $(GEN))/generic_fifo_sc_a.v $(TB)
	cd $(BUILD)/xsim && xelab -debug typical -s $(TOP) work.$(TOP)
	cd $(BUILD)/xsim && xsim $(TOP) -R -testplusarg TRACE=trace.csv

compare: verilator xsim
	python3 $(COMPARE) $(BUILD)/verilator/trace.csv $(BUILD)/xsim/trace.csv

clean:
	rm -rf $(BUILD)
