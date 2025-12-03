###############
#
#  Shared XSIM (Vivado xvlog/xelab/xsim) parity-harness build logic.
#
#  Include this from any sim/verilator/test_* Makefile that has its own
#  tb_higgs_top_xsim.sv (the per-test hand-written SV testbench mirroring
#  that test's tb.cpp exactly -- this file only builds/runs the shared
#  DUT plumbing, never the per-test stimulus/self-check).
#
#  Requires HIGGS_ROOT, Q_ENGINE_REPO, IP_LIBRARY_REPO, DATAPATH_REPO,
#  RISCV_BASEBAND_REPO, VER_SOURCES, VER_INCLUDE_DIRS,
#  VERILATOR_C_OVERRIDE_DEFINES, VERILATOR_TB_INCLUDE_DEFINES, and
#  VER_BINARY already defined (all of these come from
#  scripts/make_include/tb_common.mk, included before this file).
#
#  `make xsim_compare` reuses this test's own `run` output (Verilator) as
#  ground truth and diffs it against a fresh XSIM run's ring-bus log,
#  using the shared sim/verilator/compare_ringbus.py.
#

XSIM_COMMON_DIR=$(HIGGS_ROOT)/sim/verilator/xsim_common
XSIM_GEN_DIR=xsim_gen

# The 3 files below are code-generator/legacy output that Verilator (and,
# for nco.v/CS12's real synth flow, Vivado's synthesizer) tolerate but
# that XSIM's `xvlog` frontend rejects outright (forward-net-reference for
# nco.v; duplicate signal declarations for generic_fifo_sc_a.v; and a
# `` `timescale `` directive on the latter two that conflicts with xelab's
# all-or-nothing rule, since none of the ~150 other files in this design
# declare one). These are the exact same 3 files/patches already proven in
# fpgas/common/xilinx/sim/vex_machine_top/Makefile; reused verbatim here
# since this design's source list is a superset of that harness's.
# All 8 csXX_top.sv files declare their `snap_io_uart_txd`/`_rxd` ports
# with no explicit net type (legal, and treated as an implicit `wire`, by
# Verilator even under `` `default_nettype none ``); XSIM's `xvlog`
# frontend enforces the stricter LRM reading and rejects this as a hard
# error for every one of these 8 files, since xvlog statically analyzes
# every provided source file whether or not it ends up instantiated under
# tb_higgs_top's current `` `ifdef TB_USE_* `` set (only cs20_top is
# actually instantiated for this test, but all 8 must still compile
# cleanly). All 8 also declare their internal `gpio` net as `logic [21:0]`
# and connect it straight to their vex_machine_top instance's `inout gpio`
# port; Verilator tolerates a `logic` variable on an inout port, but
# XSIM's elaborator (xelab) rejects connecting a non-net variable to an
# inout port outright (needs an actual `wire` for tri-state resolution).
# All 8 share these exact same three lines (mechanically generated/
# copy-pasted from a common template); patched identically here.
CS_FPGA_NAMES=cs20 cs01 cs11 cs21 cs31 cs32 cs22 cs12 cs02

# eth_top.sv (unconditionally instantiated by tb_higgs_top.sv, so it is
# genuinely part of this test's DUT, unlike the other 7 cs*_top.sv files
# above) has the same class of implicit-net-type ports (CLK, LED_D4/D12,
# HS_EAST_OUT, HS_EAST_OUT_RST, and the MAC_RX_*/MAC_TX_* ports active
# when ETH_USE_MEGA_WRAPPER is undefined, as it is here), plus a genuine
# copy-paste duplicate declaration: `split_fb_data`/`split_fb_valid`/
# `split_fb_ready` are declared as ANSI ports (lines 139-141) *and*
# redeclared as `reg` internally (lines 503-504) alongside the one
# legitimately-internal signal in that same statement, `split_fb_last`.
# Verilator/Vivado's synthesizer tolerate both; xvlog rejects both.
#
# The implicit-net-type-port issue (see eth_top.sv's comment above) turns
# out to be pervasive across this legacy codebase's *.sv files, well
# beyond the FPGA top-levels: xvlog statically analyzes every file in
# VER_SOURCES regardless of whether tb_higgs_top's current `` `ifdef ``
# set actually instantiates it (e.g. eth_mega_wrapper.sv/eth_rx_wrapper.sv
# are only reachable when ETH_USE_MEGA_WRAPPER is defined, which it is not
# here, yet must still compile cleanly standalone). All of the files below
# need nothing beyond that one generic fix, so xsim_gen applies the same
# regex used for dac/adc/cfg (insert `wire` into any bare `input`/`output`
# port lacking an explicit net type, only after each file's own
# `` `default_nettype none ``) to all of them in a single loop.
GENERIC_NET_TYPE_PATCHED_SOURCES=\
	$(HIGGS_ROOT)/fpgas/grav/dac/hdl/dac_top.sv \
	$(HIGGS_ROOT)/fpgas/grav/adc/hdl/adc_top.sv \
	$(HIGGS_ROOT)/fpgas/grav/cfg/hdl/cfg_top.sv \
	$(HIGGS_ROOT)/fpgas/common/modules/cmd_cdc.sv \
	$(HIGGS_ROOT)/fpgas/common/modules/width_convert/width_32_8.sv \
	$(HIGGS_ROOT)/fpgas/common/modules/width_convert/width_8_32.sv \
	$(HIGGS_ROOT)/fpgas/grav/eth/hdl/eth_mega_wrapper.sv \
	$(HIGGS_ROOT)/fpgas/grav/eth/hdl/eth_rx_wrapper.sv \
	$(IP_LIBRARY_REPO)/lattice_support/gbit_mac/modules/arp_reply/hdl/arp_reply.sv \
	$(IP_LIBRARY_REPO)/lattice_support/gbit_mac/modules/mac_tx_arbiter/hdl/mac_tx_arbiter.sv \
	$(IP_LIBRARY_REPO)/lattice_support/gbit_mac/modules/udp_rx_stream_buffer/hdl/udp_rx_stream_buffer.sv \
	$(IP_LIBRARY_REPO)/lattice_support/gbit_mac/modules/udp_packetizer/hdl/udp_packetizer.sv

# The Q-engine/piston IP below (48 files: everything from libs/q-engine
# reachable by this design) was written and only ever verified against
# Verilator, whose 2-state engine implicitly starts every `reg` at 0. XSIM
# is a real 4-state simulator: an unreset `reg` stays X until its first
# write, and this IP's elastic-pipeline handshake idioms often gate that
# first write behind an expression that itself reads the (still-X) reg
# (see e.g. vector_slice.v's i0_latched/k15_latched, discovered via a
# live hang -- xbaseband_cmd_ready stuck low forever with iBus_cmd_
# payload_pc frozen mid-fft1024 -- and then confirmed systemic via an
# xsim tclbatch scan of piston_inst's ~10k signals, which found ~992
# permanently-X regs across dozens of these files), so the X can never
# resolve, permanently poisoning downstream valid/ready logic. On real
# silicon this is a non-issue: synthesis programs each flip-flop's
# power-on `INIT` bitstream attribute to 0 absent an explicit initial
# value, exactly matching Verilator's assumption; only XSIM's
# pre-synthesis behavioral semantics are uniquely pessimistic here.
# xsim_reg_init_fix.py mechanically adds `= 1'b0` to every internal,
# non-array `reg` declaration lacking one (conservatively skipping memory
# arrays and anything already reset/initialized) across all of these
# files in one pass -- see its docstring and README.md for the full
# derivation and why this is behavior-preserving for both Verilator and
# real hardware.
Q_ENGINE_REG_INIT_SOURCES=\
	$(Q_ENGINE_REPO)/hdl/dma/dma_in.v \
	$(Q_ENGINE_REPO)/hdl/dma/dma_in_dummy.v \
	$(Q_ENGINE_REPO)/hdl/dma/dma_out.v \
	$(Q_ENGINE_REPO)/hdl/nco/nco_gen.v \
	$(Q_ENGINE_REPO)/hdl/q_engine.v \
	$(Q_ENGINE_REPO)/hdl/ring_bus/ring_bus.v \
	$(Q_ENGINE_REPO)/hdl/scalar_memory.v \
	$(Q_ENGINE_REPO)/hdl/slicer.v \
	$(Q_ENGINE_REPO)/piston/hdl/bs_dat_2_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/cfg_ctrl.v \
	$(Q_ENGINE_REPO)/piston/hdl/cfg_dat.v \
	$(Q_ENGINE_REPO)/piston/hdl/defunnel_ctrl_3_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/defunnel_dat_3_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/eb15_ctrl.v \
	$(Q_ENGINE_REPO)/piston/hdl/eb17_ctrl.v \
	$(Q_ENGINE_REPO)/piston/hdl/eb_fifo_ctrl.v \
	$(Q_ENGINE_REPO)/piston/hdl/funnel_ctrl_2_2.v \
	$(Q_ENGINE_REPO)/piston/hdl/funnel_dat_2_2.v \
	$(Q_ENGINE_REPO)/piston/hdl/inmux_ctrl_4_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/inmux_dat_4_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/iperm_ctrl_2_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/iperm_dat_2_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/k15_op.v \
	$(Q_ENGINE_REPO)/piston/hdl/ka_decode_ctrl_1_3.v \
	$(Q_ENGINE_REPO)/piston/hdl/ka_decode_dat_1_3.v \
	$(Q_ENGINE_REPO)/piston/hdl/kap_ctrl_ctrl_1_5.v \
	$(Q_ENGINE_REPO)/piston/hdl/kap_ctrl_dat_1_5.v \
	$(Q_ENGINE_REPO)/piston/hdl/memory_slice.v \
	$(Q_ENGINE_REPO)/piston/hdl/operm_ctrl_2_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/operm_dat_2_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/oumux_ctrl_2_5.v \
	$(Q_ENGINE_REPO)/piston/hdl/oumux_dat_2_5.v \
	$(Q_ENGINE_REPO)/piston/hdl/p_decode_ctrl_1_2.v \
	$(Q_ENGINE_REPO)/piston/hdl/p_decode_dat_1_2.v \
	$(Q_ENGINE_REPO)/piston/hdl/perm_addr_dat_1_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/perm_addr_slice.v \
	$(Q_ENGINE_REPO)/piston/hdl/perm_data_dat_2_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/perm_data_slice.v \
	$(Q_ENGINE_REPO)/piston/hdl/perm_full_addr_dat_1_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/perm_full_data_dat_2_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/permutator_slice.v \
	$(Q_ENGINE_REPO)/piston/hdl/piston.v \
	$(Q_ENGINE_REPO)/piston/hdl/round_sat_dat_1_1.v \
	$(Q_ENGINE_REPO)/piston/hdl/vector_ctrl_17_2.v \
	$(Q_ENGINE_REPO)/piston/hdl/vector_dat_17_2.v \
	$(Q_ENGINE_REPO)/piston/hdl/vector_slice.v \
	$(Q_ENGINE_REPO)/piston/hdl/vmem_ctrl_6_5.v \
	$(Q_ENGINE_REPO)/piston/hdl/vmem_dat_6_5.v

# fwft_sc_fifo.v (the first-word-fall-through wrapper generic_fifo_sc_a.v
# is instantiated inside) has the exact same missing-reset-register bug:
# its `fifo_rdata_buf` holding-buffer data register is only ever written
# inside `if(rden)`/`else if(fifo_rdata_vld)` branches with no reset
# branch, so it stays X in XSIM until the first such write.
FIFO_REG_INIT_SOURCES=\
	$(IP_LIBRARY_REPO)/fwft_fifos/sc_fifo/hdl/fwft_sc_fifo.v

# XbbRiscv.v (the RISC-V CPU core itself, SpinalHDL-generated) has the
# same bug pattern at a much larger scale (~500 bare `reg`s): e.g.
# slicer.v's r_config_payload_slice is fed directly from this core's
# `dma_1_config_payload_slicer` CSR output, which is itself computed
# combinationally in XbbRiscv.v from further internal pipeline regs; if
# any upstream contributor is momentarily X (as many of these ~500
# registers were before this fix), the X propagates all the way out to
# slicer.v's enable_out/i0_valid and ultimately ringbus_out_data_vld,
# exactly the same failure mode as the q-engine/piston case above. This
# was tracked down via a live tclbatch probe: ringbus_out_data_vld
# glitched to X for a single cycle at a time, traced back through
# slicer_0/enable_out (X) -> r_config_payload_slice (X for that cycle)
# -> dma_1_config_payload_slicer (X, driven straight out of XbbRiscv.v).
RISCV_REG_INIT_SOURCES=\
	$(RISCV_BASEBAND_REPO)/hdl/generated/XbbRiscv.v

REG_INIT_SOURCES=$(Q_ENGINE_REG_INIT_SOURCES) $(FIFO_REG_INIT_SOURCES) $(RISCV_REG_INIT_SOURCES)

# core_top.sv's SYS_CLK_SRSTS_EXTRA_CLOCKS/MIB_CLK_SRSTS_EXTRA_CLOCKS
# unpacked-array parameters use packed-replication syntax (`{N{val}}`) for
# their default value; Verilator accepts this as an extension, but per
# strict IEEE1800 LRM, unpacked-array replication requires the `` '{ }``
# assignment-pattern form (`` '{N{val}}``), which xvlog enforces. Purely a
# default-value literal syntax fix (values/widths unchanged).
# eth_top.sv's own instantiation of core_top overrides
# MIB_CLK_SRSTS_EXTRA_CLOCKS (an unpacked int array, size
# NUM_MIB_CLK_SRSTS=1 here) with a bare scalar `1'b0`; xelab's static
# elaboration rejects this packed-to-unpacked assignment (VRFC 10-395),
# so it is rewritten to the single-element array-literal form `'{1'b0}`.
# Interestingly this only surfaces as an elaboration error in some test
# configurations (not test_fft_lib_1's), likely due to elaboration-order/
# optimizer differences across designs; the fix is harmless either way.
# core_reset.sv's EXTRA_RESET_CLOCKS unpacked-array parameter default
# assigns a bare scalar `0` (broadcast-to-fill, a Verilator extension);
# xvlog requires the LRM assignment-pattern form.
XSIM_PATCHED_SOURCES=\
	$(Q_ENGINE_REPO)/hdl/nco/nco.v \
	$(REG_INIT_SOURCES) \
	$(IP_LIBRARY_REPO)/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v \
	$(DATAPATH_REPO)/rtl/muladdsub.v \
	$(HIGGS_ROOT)/fpgas/grav/eth/hdl/eth_top.sv \
	$(HIGGS_ROOT)/fpgas/common/modules/core_top.sv \
	$(HIGGS_ROOT)/fpgas/common/modules/core_reset.sv \
	$(GENERIC_NET_TYPE_PATCHED_SOURCES) \
	$(foreach n,$(CS_FPGA_NAMES),$(HIGGS_ROOT)/fpgas/cs/$(n)/hdl/$(n)_top.sv)

XSIM_SOURCES=\
	$(filter-out $(XSIM_PATCHED_SOURCES),$(VER_SOURCES)) \
	$(XSIM_GEN_DIR)/nco.v \
	$(foreach f,$(REG_INIT_SOURCES),$(XSIM_GEN_DIR)/$(notdir $(f))) \
	$(XSIM_GEN_DIR)/generic_fifo_sc_a.v \
	$(XSIM_GEN_DIR)/muladdsub.v \
	$(XSIM_GEN_DIR)/core_top.sv \
	$(XSIM_GEN_DIR)/core_reset.sv \
	$(XSIM_GEN_DIR)/eth_top.sv \
	$(foreach f,$(GENERIC_NET_TYPE_PATCHED_SOURCES),$(XSIM_GEN_DIR)/$(notdir $(f))) \
	$(foreach n,$(CS_FPGA_NAMES),$(XSIM_GEN_DIR)/$(n)_top.sv)

# Translate Verilator's `+define+NAME=VAL` / `-Ipath` conventions (shared,
# via tb_common.mk/makefile_sim_verialtor.mk, with the `verilate` target
# above) into xvlog's `-d NAME=VAL` / `-i path` equivalents. Word-wise
# $(patsubst) only rewrites the matching prefix of each space-separated
# token, so escaped-quote string values (e.g. CS20_SCALAR_0's .mif path)
# pass through unchanged.
#
# EXTRA_RINGBUS is normally enabled by a local `` `define EXTRA_RINGBUS ``
# in fpgas/grav/eth/hdl/eth_top.sv, right before its q_engine instantiation.
# Verilog `` `define `` has file-order-dependent (not instantiation-site-
# scoped) effect: since q_engine.v (the module *definition*, compiled once)
# is analyzed by xvlog before eth_top.sv in XSIM_SOURCES order, that local
# `` `define `` is too late to affect q_engine.v's own `` `ifdef
# EXTRA_RINGBUS `` guard, so XSIM silently skips instantiating q_engine's
# second ring_bus (ring_bus_inst_2), leaving eth_top's o_ringbus floating
# and HS_EAST_OUT_RB[47] latching X/Z -- breaking the CS-tile-to-ETH
# ring-bus return path (first observed via test_dma_fft, whose CS11/12/02/01
# ring_block_send_eth() boot messages never reached ETH under XSIM).
# Verilator already instantiates ring_bus_inst_2 for every q_engine instance
# (confirmed via obj_dir/*ring_bus* symbols), so defining EXTRA_RINGBUS
# globally here on the command line (order-independent) makes XSIM match
# Verilator's actual compiled behavior exactly.
XSIM_DEFINES=\
	$(patsubst +define+%,-d %,$(VERILATOR_C_OVERRIDE_DEFINES) $(VERILATOR_TB_INCLUDE_DEFINES)) \
	-d VERILATE -d VERILATE_DEF -d LOAD_VMEM -d EXTRA_RINGBUS

XSIM_INCLUDES=$(patsubst -I%,-i %,$(VER_INCLUDE_DIRS))

XSIM_TB=tb_higgs_top_xsim.sv
XSIM_TOP=tb_higgs_top_xsim

.PHONY: xsim_gen xsim_compile xsim_elab xsim_run xsim xsim_clean xsim_compare verilator_run_log

xsim_gen:
	mkdir -p $(XSIM_GEN_DIR)
	python3 -c "\
import re; \
src = open('$(Q_ENGINE_REPO)/hdl/nco/nco.v').read(); \
src = src.replace(');\n// per edge', ');\nwire [8:0] node1_addr; // build-only hoist, see README.md\n// per edge', 1); \
src = src.replace('wire [8:0] node1_addr;\n', '', 1); \
open('$(XSIM_GEN_DIR)/.nco_fwdref.v', 'w').write(src)"
	python3 $(XSIM_COMMON_DIR)/xsim_reg_init_fix.py $(XSIM_GEN_DIR)/.nco_fwdref.v $(XSIM_GEN_DIR)
	mv $(XSIM_GEN_DIR)/.nco_fwdref.v $(XSIM_GEN_DIR)/nco.v
	for f in $(REG_INIT_SOURCES); do \
	  python3 $(XSIM_COMMON_DIR)/xsim_reg_init_fix.py $$f $(XSIM_GEN_DIR); \
	done
	sed -e '/^   reg                    full_r;$$/d' \
	    -e '/^   reg                    empty_r;$$/d' \
	    -e '/^   wire                   full_n, empty_n;$$/d' \
	    -e '/^   reg                    full_n_r, empty_n_r;$$/d' \
	    -e '/^`timescale 1ns \/ 100ps$$/d' \
	    $(IP_LIBRARY_REPO)/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v > $(XSIM_GEN_DIR)/generic_fifo_sc_a.v
	sed -e '/^`timescale 1 ns \/ 1 ps$$/d' \
	    $(DATAPATH_REPO)/rtl/muladdsub.v > $(XSIM_GEN_DIR)/muladdsub.v
	for n in $(CS_FPGA_NAMES); do \
	  tr -d '\r' < $(HIGGS_ROOT)/fpgas/cs/$$n/hdl/$${n}_top.sv \
	  | sed -e 's/^\( *\)output *snap_io_uart_txd,/\1output wire        snap_io_uart_txd,/' \
	        -e 's/^\( *\)input *snap_io_uart_rxd,/\1input  wire        snap_io_uart_rxd,/' \
	        -e 's/^\( *\)logic \[21:0\] gpio;/\1wire  [21:0] gpio;/' \
	  > $(XSIM_GEN_DIR)/$${n}_top.sv; \
	done
	sed \
	  -e 's/^    input               CLK,$$/    input  wire         CLK,/' \
	  -e 's/^    output              LED_D4, \/\/ Red$$/    output wire         LED_D4, \/\/ Red/' \
	  -e 's/^    output              LED_D12, \/\/ Yellow$$/    output wire         LED_D12, \/\/ Yellow/' \
	  -e 's/^    output \[34:2\]       HS_EAST_OUT, \/\/ 32 = DAC data Valid, 31:0 = DAC Data$$/    output wire [34:2]  HS_EAST_OUT, \/\/ 32 = DAC data Valid, 31:0 = DAC Data/' \
	  -e 's/^    output \[46:46\]      HS_EAST_OUT_RST,$$/    output wire [46:46] HS_EAST_OUT_RST,/' \
	  -e 's/^    input               MAC_RX_WRITE,$$/    input  wire         MAC_RX_WRITE,/' \
	  -e 's/^    input               MAC_RX_EOF,$$/    input  wire         MAC_RX_EOF,/' \
	  -e 's/^    input \[7:0\]         MAC_RX_FIFODATA,$$/    input  wire [7:0]   MAC_RX_FIFODATA,/' \
	  -e 's/^    output              MAC_TX_FIFOAVAIL,$$/    output wire         MAC_TX_FIFOAVAIL,/' \
	  -e 's/^    output \[7:0\]        MAC_TX_FIFODATA,$$/    output wire [7:0]   MAC_TX_FIFODATA,/' \
	  -e 's/^    output              MAC_TX_FIFOEOF,$$/    output wire         MAC_TX_FIFOEOF,/' \
	  -e 's/^    input               MAC_TX_MACREAD$$/    input  wire         MAC_TX_MACREAD/' \
	  -e '/^   reg \[31:0\]     split_fb_data;$$/d' \
	  -e 's/^   reg            split_fb_valid, split_fb_last, split_fb_ready;$$/   reg            split_fb_last;/' \
	  -e '/^   \/\/assign ENET_CTRL_RESETN = 1'"'"'b1;$$/i\
   wire [21:0]  gpio; // build-only hoist (forward reference), see README.md' \
	  -e '/^   wire \[21:0\]  gpio;$$/d' \
	  -e "s/\.MIB_CLK_SRSTS_EXTRA_CLOCKS         (1'b0),/.MIB_CLK_SRSTS_EXTRA_CLOCKS         ('{1'b0}),/" \
	  $(HIGGS_ROOT)/fpgas/grav/eth/hdl/eth_top.sv > $(XSIM_GEN_DIR)/eth_top.sv
	sed -e "s/= {NUM_SYS_CLK_SRSTS{1'b0}}/= '{NUM_SYS_CLK_SRSTS{1'b0}}/g" \
	    $(HIGGS_ROOT)/fpgas/common/modules/core_top.sv > $(XSIM_GEN_DIR)/core_top.sv
	sed -e "s/= 0 \/\/ allows you to specify how many additional clocks/= '{default: 0} \/\/ allows you to specify how many additional clocks/" \
	    $(HIGGS_ROOT)/fpgas/common/modules/core_reset.sv > $(XSIM_GEN_DIR)/core_reset.sv
	for f in $(GENERIC_NET_TYPE_PATCHED_SOURCES); do \
	  python3 $(XSIM_COMMON_DIR)/xsim_net_type_fix.py $$f $(XSIM_GEN_DIR); \
	done

xsim_compile: xsim_gen
	command -v xvlog >/dev/null
	xvlog -sv $(XSIM_DEFINES) $(XSIM_INCLUDES) $(XSIM_SOURCES) $(XSIM_TB)

xsim_elab: xsim_compile
	command -v xelab >/dev/null
	# --timescale: a handful of libs/ip-library/*.sv files carry an explicit
	# `timescale directive while most of the design (and tb_higgs_top.sv) do
	# not; Vivado requires every module in the design to agree, so supply the
	# same 1ns/1ps default Verilator implicitly assumes for undecorated files.
	# No --debug: this is a batch $display-only smoke test (no waveform/
	# breakpoint needs), and "-debug typical" pulls in wave/driver tracing
	# infrastructure that made a ~700k-cycle run enormously slower.
	xelab --timescale 1ns/1ps -s $(XSIM_TOP) work.$(XSIM_TOP)

xsim_run: xsim_elab
	command -v xsim >/dev/null
	xsim $(XSIM_TOP) -R | tee xsim_run.log

xsim: xsim_run

xsim_clean:
	rm -rf $(XSIM_GEN_DIR) xsim.dir xsim_run.log xsim.jou *.wdb
	rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log webtalk*.jou webtalk*.log
	rm -rf .Xil

# Ground truth is this same test's existing Verilator binary (built via
# the compilehex/verilate/compile targets tb_common.mk already defines
# above); this just also captures its stdout to a log (rather than
# re-defining the shared `run` target) and diffs both simulators' ring-bus
# output streams.
verilator_run_log: compile
	./obj_dir/$(VER_BINARY) | tee verilator_run.log

xsim_compare: verilator_run_log xsim_run
	python3 $(HIGGS_ROOT)/sim/verilator/compare_ringbus.py verilator_run.log xsim_run.log
