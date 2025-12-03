// XSIM parity testbench for this test's actual DUT: `tb_higgs_top`
// (sim/hdl/tb_higgs_top.sv). Port list/instantiation reused verbatim
// from test_cs20_dma's testbench (byte-identical TB_USE_CS* set: all 9
// FPGA tiles), since this test's Makefile also sets TB_USE_CS11/CS12/
// CS02/CS01/CS31/CS32/CS22/CS21/CS20=1 -- see that file's header comment
// for the full per-tile port-bundle derivation (cs11/cs31 monitor-only
// riscv_in taps, cs22/cs21 tied-off inject_riscv_in, etc). The only
// structural difference from test_cs20_dma's DUT config is which tiles
// have real firmware (OVERRIDE_CS11/CS12/CS02/CS01_C=1 here, vs
// OVERRIDE_CS20_C=1 there) -- this doesn't change the port list at all,
// only which compiled hex/mem-init content xsim_common.mk's shared
// VERILATOR_C_OVERRIDE_DEFINES-based hex loading feeds in.
//
// This test (see README.md) is fundamentally different from the other
// three DMA ports: it's a **randomized glitch-detection regression**,
// not a fixed-stimulus/fixed-output self-check. tb.cpp's own default
// mode (`fixed_seed = 0`) reseeds from wall-clock time every run, which
// is not reproducible across separate Verilator invocations, let alone
// across simulators -- so for genuine XSIM/Verilator parity, tb.cpp has
// been changed to `fixed_seed = 1525241634` (a value the file's own
// author had already recorded in a comment as historically interesting,
// "After 1900"). With this fixed seed, the current codebase's Verilator
// baseline reproducibly PASSES (does not hit the historical DMA glitch
// bug the README describes -- that legacy bug is apparently already
// fixed, or this particular seed does not trigger it; this harness
// proves parity of *current* behavior, not the historical bug).
//
// To get true bit-exact stimulus parity (not just "a similarly-shaped
// random pattern"), this testbench reimplements glibc's rand()/srand()
// TYPE_3 algorithm (deg=31, sep=3 additive feedback generator) exactly
// -- see the `rand_srandom`/`rand_next` task/function below -- verified
// bit-for-bit against actual glibc rand() output for this seed via a
// standalone C cross-check before writing this file. Seeded identically
// and called in the exact same sequence as tb.cpp's `pick = rand()`
// calls, this produces the IDENTICAL cs11in injection-timing schedule
// in both simulators (confirmed no other rand() call sites are reachable
// before/during this test's stimulus loop: no port here has
// random_valid/random_ready set non-zero, so higgs_helper.hpp's own
// internal rand() call sites are never exercised).
//
// Mirrors tb.cpp's actual stimulus loop exactly:
//  - t->reset(40) -> RESET_CYCLES = 40 (see test_fft_lib_1's header
//    comment for the half-edge-counter derivation).
//  - postReset(top) -> i_data_valid_adc driven to 1.
//  - `unsigned int pick = rand();` (the *first* rand() draw after
//    srand(), consumed once before the main loop) -> `pick =
//    rand_next()` called once, identically, before the main loop below.
//  - `for (i = 0; i < us*500; i++) { ... t->tick(1); }` with
//    `us = 2100` -> TOTAL_CYCLES = 2100*500 = 1,050,000 single-cycle
//    iterations (INJECT_START = 500*100 = 50000, matching `i >
//    500*100`).
//    - Injection: `if ((i % (20 + pick%128)) == 0) { if (i >
//      INJECT_START) { pick = rand(); inStreamAppend("cs11in", vin); } }`
//      -- reproduced exactly, including the fact that `pick` only
//      updates (and only injects) on hits *after* INJECT_START. vin =
//      {0..31} pushed to a queue (matching HiggsHelper's
//      VEC_R_APPEND-then-pop_back FIFO semantics, verified to reduce to
//      plain push_back+pop_front ordering for a single isolated batch).
//    - "cs11in" (`tx_turnstile_data_in/last/valid/ready`, see
//      higgs_helper.hpp: `t_data=&top->tx_turnstile_data_in`, etc, NOT
//      the `snap_cs11_riscv_in_*` monitor tap -- that's a different,
//      unrelated port) is a genuine testbench-driven valid/ready input
//      (`respect_ready=true`): driven combinationally from the queue's
//      occupancy, popped on `valid && ready` at each posedge, exactly
//      matching handleDataInNegIndex/PosIndex's queue-based semantics.
//      `tx_turnstile_data_last` is never referenced by higgs_helper.hpp
//      for this port and stays tied to 0 (matching Verilator leaving an
//      unassigned top-level input signal at its power-on-reset value).
//    - Early-break self-check: `if ((i % 1000) == 0) { scan
//      outs["ringbusout"]->data for 0xc000001; if found, break }` --
//      reproduced by scanning the accumulated `ring_items` queue (see
//      ring-bus capture below, identical to test_fft_lib_1's) every
//      1000 cycles.
//  - ring-bus capture/print: identical convention to test_fft_lib_1's
//    (`ring_bus_i0_ready && ringbus_out_data_vld` gate, `$display("0x
//    %0h", ...)` per item), matching `t->print_ringbus_out()`'s
//    "Ringbus got out N items" + one "0x<hex>" line per item.
//  - final self-check: PASS unless the 0xc000001 glitch code was ever
//    observed on the ring bus (matching tb.cpp's
//    `assert(test_failed == false && "Test Failed, output dma glitch")`).
//
// See tb.cpp, higgs_helper.hpp (preReset/postReset/reset,
// inStreamAppend/handleDataInNegIndex/PosIndex) and README.md for the
// full derivation of the stimulus/tie-off table above.
//
// Deliberately has no `` `timescale `` directive of its own -- see
// test_fft_lib_1/tb_higgs_top_xsim.sv's header comment for why (xelab
// requires every module in a design to consistently either have or lack
// a timescale, and none of the ~150 files reachable from tb_higgs_top
// declare one, aside from the patched exceptions the shared
// scripts/make_include/xsim_common.mk handles).

module tb_higgs_top_xsim;

  localparam int RESET_CYCLES  = 40;
  localparam int INJECT_START  = 500*100; // 50000
  localparam int TOTAL_CYCLES  = 2100*500; // 1,050,000
  localparam int CHECK_PERIOD  = 1000;
  localparam int unsigned SEED = 1525241634;
  localparam int GLITCH_CODE   = 32'h0c000001;

  // ---- glibc rand()/srand() TYPE_3 reimplementation (deg=31, sep=3) --
  // verified bit-for-bit against actual libc rand()/srand() for SEED
  // via a standalone C program before writing this file. See header
  // comment above.
  localparam int DEG = 31;
  localparam int SEP = 3;
  int rand_state[0:DEG-1];
  int rand_fptr, rand_rptr;

  task automatic rand_srandom(input int unsigned seed);
    int word;
    int hi, lo;
    int i;
    word = (seed == 0) ? 1 : int'(seed);
    rand_state[0] = word;
    for (i = 1; i < DEG; i++) begin
      hi = word / 127773;
      lo = word % 127773;
      word = 16807 * lo - 2836 * hi;
      if (word < 0) word = word + 2147483647;
      rand_state[i] = word;
    end
    rand_fptr = SEP;
    rand_rptr = 0;
    for (i = 0; i < DEG*10; i++) begin
      rand_state[rand_fptr] = rand_state[rand_fptr] + rand_state[rand_rptr];
      rand_fptr = (rand_fptr == DEG-1) ? 0 : rand_fptr+1;
      rand_rptr = (rand_rptr == DEG-1) ? 0 : rand_rptr+1;
    end
  endtask

  function automatic int unsigned rand_next();
    int unsigned result;
    rand_state[rand_fptr] = rand_state[rand_fptr] + rand_state[rand_rptr];
    result = ($unsigned(rand_state[rand_fptr]) >> 1) & 32'h7fffffff;
    rand_fptr = (rand_fptr == DEG-1) ? 0 : rand_fptr+1;
    rand_rptr = (rand_rptr == DEG-1) ? 0 : rand_rptr+1;
    return result;
  endfunction

  logic clk = 0;
  always #5 clk = ~clk;

  logic        MIB_MASTER_RESET     = 1;

  logic [31:0] i_data_adc           = 0;
  logic        i_data_valid_adc     = 0;

  // cs11in: a genuine testbench-driven valid/ready input (`respect_ready
  // = true` in higgs_helper.hpp). Driven entirely from within the
  // stimulus `initial` block's per-cycle loop below (NOT a separate
  // always_comb/always process) -- XSIM does not support sensitivity on
  // queue elements (`always_comb` referencing `cs11in_q.size()`/`[0]`
  // triggers a "Sensitivity ... is not supported" warning and silently
  // never re-evaluates), and keeping all `cs11in_q` reads/writes in one
  // process also avoids any inter-process race on which order the
  // per-cycle push (this cycle's injection) vs pop (this cycle's
  // handshake) would otherwise resolve in.
  logic [31:0] tx_turnstile_data_in    = 0;
  logic        tx_turnstile_data_last  = 0; // never referenced by higgs_helper.hpp for this port
  logic        tx_turnstile_data_valid = 0;
  wire         tx_turnstile_data_ready;

  logic [31:0] cs11in_q[$];

  logic [31:0] ringbus_in_data      = 0;
  logic        ringbus_in_data_vld  = 0;
  wire         ringbus_in_data_ready;

  wire         snap_eth_io_uart_txd;
  // UART RX idle state is logic-1 (mark/idle); see
  // test_fft_lib_1/tb_higgs_top_xsim.sv's header comment for the full
  // derivation. This test's eth firmware is the DEFAULT (no
  // OVERRIDE_ETH_C), same default polling-loop firmware that caused the
  // spurious-retrigger bug found there if left idle-low; kept idle-high
  // for correctness/consistency.
  logic        snap_eth_io_uart_rxd = 1;

  wire [31:0]  ringbus_out_data;
  wire         ringbus_out_data_vld;

  logic        ring_bus_i0_ready    = 1;

  wire         o_data_valid_dac;
  wire [31:0]  o_data_dac;

  // CS11
  wire [31:0]  snap_cs11_riscv_out_data;
  wire         snap_cs11_riscv_out_last;
  wire         snap_cs11_riscv_out_valid;
  wire         snap_cs11_riscv_out_ready;
  wire [31:0]  snap_cs11_riscv_in_data;
  wire         snap_cs11_riscv_in_valid;
  wire         snap_cs11_riscv_in_ready;
  wire         snap_cs11_io_uart_txd;
  wire         snap_cs11_io_uart_rxd;

  // CS01
  wire [31:0]  snap_cs01_riscv_out_data;
  wire         snap_cs01_riscv_out_last;
  wire         snap_cs01_riscv_out_valid;
  wire         snap_cs01_riscv_out_ready;
  wire         snap_cs01_io_uart_txd;
  wire         snap_cs01_io_uart_rxd;

  // CS31
  wire [31:0]  snap_cs31_riscv_out_data;
  wire         snap_cs31_riscv_out_last;
  wire         snap_cs31_riscv_out_valid;
  wire         snap_cs31_riscv_out_ready;
  wire         snap_cs31_io_uart_txd;
  wire         snap_cs31_io_uart_rxd;
  wire [31:0]  snap_cs31_riscv_in_data;
  wire         snap_cs31_riscv_in_last;
  wire         snap_cs31_riscv_in_valid;
  wire         snap_cs31_riscv_in_ready;

  // CS32
  wire [31:0]  snap_cs32_riscv_out_data;
  wire         snap_cs32_riscv_out_last;
  wire         snap_cs32_riscv_out_valid;
  wire         snap_cs32_riscv_out_ready;
  wire         snap_cs32_io_uart_txd;
  wire         snap_cs32_io_uart_rxd;

  // CS22 (+ inject_cs22_riscv_in_*, tied to inactive -- see header comment)
  wire [31:0]  snap_cs22_riscv_out_data;
  wire         snap_cs22_riscv_out_last;
  wire         snap_cs22_riscv_out_valid;
  wire         snap_cs22_riscv_out_ready;
  logic [31:0] inject_cs22_riscv_in_data  = 0;
  logic        inject_cs22_riscv_in_last  = 0;
  logic        inject_cs22_riscv_in_valid = 0;
  wire         inject_cs22_riscv_in_ready;
  wire         snap_cs22_io_uart_txd;
  wire         snap_cs22_io_uart_rxd;

  // CS21 (+ inject_cs21_riscv_in_*, tied to inactive -- see header comment)
  wire [31:0]  snap_cs21_riscv_out_data;
  wire         snap_cs21_riscv_out_last;
  wire         snap_cs21_riscv_out_valid;
  wire         snap_cs21_riscv_out_ready;
  logic [31:0] inject_cs21_riscv_in_data  = 0;
  logic        inject_cs21_riscv_in_last  = 0;
  logic        inject_cs21_riscv_in_valid = 0;
  wire         inject_cs21_riscv_in_ready;
  wire         snap_cs21_io_uart_txd;
  wire         snap_cs21_io_uart_rxd;

  // CS20 (the tile under test -- firmware override lives here)
  wire [31:0]  snap_cs20_riscv_out_data;
  wire         snap_cs20_riscv_out_last;
  wire         snap_cs20_riscv_out_valid;
  wire         snap_cs20_riscv_out_ready;
  wire         snap_cs20_io_uart_txd;
  wire         snap_cs20_io_uart_rxd;

  // CS02
  wire [31:0]  snap_cs02_riscv_out_data;
  wire         snap_cs02_riscv_out_last;
  wire         snap_cs02_riscv_out_valid;
  wire         snap_cs02_riscv_out_ready;
  wire         snap_cs02_io_uart_txd;
  wire         snap_cs02_io_uart_rxd;

  // CS12
  wire [31:0]  snap_cs12_riscv_out_data;
  wire         snap_cs12_riscv_out_last;
  wire         snap_cs12_riscv_out_valid;
  wire         snap_cs12_riscv_out_ready;
  wire         snap_cs12_io_uart_txd;
  wire         snap_cs12_io_uart_rxd;

  logic [31:0] adc_data_out         = 0;
  logic        adc_data_out_valid   = 0;
  wire         adc_data_out_ready;

  wire [31:0]  snap_mapmov_in_data;
  wire         snap_mapmov_in_valid;
  wire         snap_mapmov_in_ready;

  wire [31:0]  o_data_eth;
  wire         o_data_valid_eth;
  wire         o_data_last_eth;

  wire [31:0]  o_rx_data_eth;
  wire         o_rx_valid_eth;
  logic        i_rx_ready_eth       = 1; // tb always asserts ready (matches Verilator control_ready=1, random_ready=false)

  wire         DAC_CTRL_SDIO;
  wire         DAC_CTRL_SDENN;
  wire         DAC_CTRL_SCLK;
  wire         DAC_CTRL_RESETN;

  tb_higgs_top dut (
    .clk                       (clk),
    .MIB_MASTER_RESET          (MIB_MASTER_RESET),

    .i_data_adc                (i_data_adc),
    .i_data_valid_adc          (i_data_valid_adc),

    .tx_turnstile_data_in      (tx_turnstile_data_in),
    .tx_turnstile_data_last    (tx_turnstile_data_last),
    .tx_turnstile_data_valid   (tx_turnstile_data_valid),
    .tx_turnstile_data_ready   (tx_turnstile_data_ready),

    .ringbus_in_data           (ringbus_in_data),
    .ringbus_in_data_vld       (ringbus_in_data_vld),
    .ringbus_in_data_ready     (ringbus_in_data_ready),

    .snap_eth_io_uart_txd      (snap_eth_io_uart_txd),
    .snap_eth_io_uart_rxd      (snap_eth_io_uart_rxd),

    .ringbus_out_data          (ringbus_out_data),
    .ringbus_out_data_vld      (ringbus_out_data_vld),

    .ring_bus_i0_ready         (ring_bus_i0_ready),

    .o_data_valid_dac          (o_data_valid_dac),
    .o_data_dac                (o_data_dac),

    .snap_cs11_riscv_out_data  (snap_cs11_riscv_out_data),
    .snap_cs11_riscv_out_last  (snap_cs11_riscv_out_last),
    .snap_cs11_riscv_out_valid (snap_cs11_riscv_out_valid),
    .snap_cs11_riscv_out_ready (snap_cs11_riscv_out_ready),
    .snap_cs11_riscv_in_data   (snap_cs11_riscv_in_data),
    .snap_cs11_riscv_in_valid  (snap_cs11_riscv_in_valid),
    .snap_cs11_riscv_in_ready  (snap_cs11_riscv_in_ready),
    .snap_cs11_io_uart_txd     (snap_cs11_io_uart_txd),
    .snap_cs11_io_uart_rxd     (snap_cs11_io_uart_rxd),

    .snap_cs01_riscv_out_data  (snap_cs01_riscv_out_data),
    .snap_cs01_riscv_out_last  (snap_cs01_riscv_out_last),
    .snap_cs01_riscv_out_valid (snap_cs01_riscv_out_valid),
    .snap_cs01_riscv_out_ready (snap_cs01_riscv_out_ready),
    .snap_cs01_io_uart_txd     (snap_cs01_io_uart_txd),
    .snap_cs01_io_uart_rxd     (snap_cs01_io_uart_rxd),

    .snap_cs31_riscv_out_data  (snap_cs31_riscv_out_data),
    .snap_cs31_riscv_out_last  (snap_cs31_riscv_out_last),
    .snap_cs31_riscv_out_valid (snap_cs31_riscv_out_valid),
    .snap_cs31_riscv_out_ready (snap_cs31_riscv_out_ready),
    .snap_cs31_io_uart_txd     (snap_cs31_io_uart_txd),
    .snap_cs31_io_uart_rxd     (snap_cs31_io_uart_rxd),
    .snap_cs31_riscv_in_data   (snap_cs31_riscv_in_data),
    .snap_cs31_riscv_in_last   (snap_cs31_riscv_in_last),
    .snap_cs31_riscv_in_valid  (snap_cs31_riscv_in_valid),
    .snap_cs31_riscv_in_ready  (snap_cs31_riscv_in_ready),

    .snap_cs32_riscv_out_data  (snap_cs32_riscv_out_data),
    .snap_cs32_riscv_out_last  (snap_cs32_riscv_out_last),
    .snap_cs32_riscv_out_valid (snap_cs32_riscv_out_valid),
    .snap_cs32_riscv_out_ready (snap_cs32_riscv_out_ready),
    .snap_cs32_io_uart_txd     (snap_cs32_io_uart_txd),
    .snap_cs32_io_uart_rxd     (snap_cs32_io_uart_rxd),

    .snap_cs22_riscv_out_data  (snap_cs22_riscv_out_data),
    .snap_cs22_riscv_out_last  (snap_cs22_riscv_out_last),
    .snap_cs22_riscv_out_valid (snap_cs22_riscv_out_valid),
    .snap_cs22_riscv_out_ready (snap_cs22_riscv_out_ready),
    .inject_cs22_riscv_in_data  (inject_cs22_riscv_in_data),
    .inject_cs22_riscv_in_last  (inject_cs22_riscv_in_last),
    .inject_cs22_riscv_in_valid (inject_cs22_riscv_in_valid),
    .inject_cs22_riscv_in_ready (inject_cs22_riscv_in_ready),
    .snap_cs22_io_uart_txd     (snap_cs22_io_uart_txd),
    .snap_cs22_io_uart_rxd     (snap_cs22_io_uart_rxd),

    .snap_cs21_riscv_out_data  (snap_cs21_riscv_out_data),
    .snap_cs21_riscv_out_last  (snap_cs21_riscv_out_last),
    .snap_cs21_riscv_out_valid (snap_cs21_riscv_out_valid),
    .snap_cs21_riscv_out_ready (snap_cs21_riscv_out_ready),
    .inject_cs21_riscv_in_data  (inject_cs21_riscv_in_data),
    .inject_cs21_riscv_in_last  (inject_cs21_riscv_in_last),
    .inject_cs21_riscv_in_valid (inject_cs21_riscv_in_valid),
    .inject_cs21_riscv_in_ready (inject_cs21_riscv_in_ready),
    .snap_cs21_io_uart_txd     (snap_cs21_io_uart_txd),
    .snap_cs21_io_uart_rxd     (snap_cs21_io_uart_rxd),

    .snap_cs20_riscv_out_data  (snap_cs20_riscv_out_data),
    .snap_cs20_riscv_out_last  (snap_cs20_riscv_out_last),
    .snap_cs20_riscv_out_valid (snap_cs20_riscv_out_valid),
    .snap_cs20_riscv_out_ready (snap_cs20_riscv_out_ready),
    .snap_cs20_io_uart_txd     (snap_cs20_io_uart_txd),
    .snap_cs20_io_uart_rxd     (snap_cs20_io_uart_rxd),

    .snap_cs02_riscv_out_data  (snap_cs02_riscv_out_data),
    .snap_cs02_riscv_out_last  (snap_cs02_riscv_out_last),
    .snap_cs02_riscv_out_valid (snap_cs02_riscv_out_valid),
    .snap_cs02_riscv_out_ready (snap_cs02_riscv_out_ready),
    .snap_cs02_io_uart_txd     (snap_cs02_io_uart_txd),
    .snap_cs02_io_uart_rxd     (snap_cs02_io_uart_rxd),

    .snap_cs12_riscv_out_data  (snap_cs12_riscv_out_data),
    .snap_cs12_riscv_out_last  (snap_cs12_riscv_out_last),
    .snap_cs12_riscv_out_valid (snap_cs12_riscv_out_valid),
    .snap_cs12_riscv_out_ready (snap_cs12_riscv_out_ready),
    .snap_cs12_io_uart_txd     (snap_cs12_io_uart_txd),
    .snap_cs12_io_uart_rxd     (snap_cs12_io_uart_rxd),

    .adc_data_out              (adc_data_out),
    .adc_data_out_valid        (adc_data_out_valid),
    .adc_data_out_ready        (adc_data_out_ready),

    .snap_mapmov_in_data       (snap_mapmov_in_data),
    .snap_mapmov_in_valid      (snap_mapmov_in_valid),
    .snap_mapmov_in_ready      (snap_mapmov_in_ready),

    .o_data_eth                (o_data_eth),
    .o_data_valid_eth          (o_data_valid_eth),
    .o_data_last_eth           (o_data_last_eth),

    .o_rx_data_eth             (o_rx_data_eth),
    .o_rx_valid_eth            (o_rx_valid_eth),
    .i_rx_ready_eth            (i_rx_ready_eth),

    .DAC_CTRL_SDIO             (DAC_CTRL_SDIO),
    .DAC_CTRL_SDENN            (DAC_CTRL_SDENN),
    .DAC_CTRL_SCLK             (DAC_CTRL_SCLK),
    .DAC_CTRL_RESETN           (DAC_CTRL_RESETN)
  );

  // ring-bus capture: identical convention to test_fft_lib_1's -- gated
  // on `ring_bus_i0_ready && ringbus_out_data_vld`, printed immediately
  // as `0x<hex>` (matching HiggsHelper::print_ringbus_out()'s per-item
  // line, parsed by compare_ringbus.py).
  int          ring_count = 0;
  logic [31:0] ring_items[$];

  always @(posedge clk) begin
    if (ring_bus_i0_ready && ringbus_out_data_vld) begin
      ring_items.push_back(ringbus_out_data);
      ring_count++;
      $display("0x%0h", ringbus_out_data);
    end
  end

  initial begin
    int i, j;
    bit  fail;
    bit  broke_early;
    int unsigned pick;

    fail = 0;
    broke_early = 0;

    // Reproduce tb.cpp's `srand(seed_start); ... unsigned int pick =
    // rand();` exactly: seed once, then draw the first pick -- this is
    // the *first* rand() call after srand() (no other rand() call site
    // is reachable before/during this test's stimulus loop; see header
    // comment).
    rand_srandom(SEED);
    pick = rand_next();

    // See test_fft_lib_1/tb_higgs_top_xsim.sv's header comment for the
    // full derivation: RESET_CYCLES (40) is a half-edge count in the C++
    // model, not a full-cycle count. Only the first (RESET_CYCLES/2 - 1)
    // = 19 rising edges see RESET==1; RESET is deasserted before the
    // 20th (final) rising edge of the reset() call.
    repeat (RESET_CYCLES/2 - 1) @(posedge clk);
    MIB_MASTER_RESET = 0;
    @(posedge clk); // the 20th (final) reset()-call cycle, RESET already 0

    // postReset(top): i_data_valid_adc driven high from here on.
    i_data_valid_adc = 1;

    // for (i = 0; i < us*500; i++) { ...; t->tick(1); } with us=2100 --
    // single-cycle loop, reproduced exactly (see header comment).
    for (i = 0; i < TOTAL_CYCLES && !broke_early; i++) begin
      if ((i % (20 + (pick % 128))) == 0) begin
        if (i > INJECT_START) begin
          pick = rand_next();
          for (j = 0; j < 32; j++) cs11in_q.push_back(j[31:0]);
        end
      end

      if ((i % CHECK_PERIOD) == 0) begin
        foreach (ring_items[idx]) begin
          if (ring_items[idx] == GLITCH_CODE) begin
            $display("Breaking early CS01 reports FAILURE at time %0t (%0d)", $time, i);
            fail = 1;
            broke_early = 1;
          end
        end
      end

      // Drive tx_turnstile_data_in/valid from the (possibly
      // just-injected) queue state for the upcoming clock edge.
      tx_turnstile_data_valid = (cs11in_q.size() > 0);
      tx_turnstile_data_in    = (cs11in_q.size() > 0) ? cs11in_q[0] : 32'h0;

      @(posedge clk);

      // Handshake completed on the edge just crossed (tx_turnstile_data_ready
      // is the DUT's combinational response, settled by now) -> pop.
      if (tx_turnstile_data_valid && tx_turnstile_data_ready) begin
        void'(cs11in_q.pop_front());
      end
    end

    $display("Ringbus got out %0d items", ring_count);

    if (fail) begin
      $display("FAIL: Test Failed, output dma glitch");
    end else begin
      $display("All Tests Passed");
      $display("Test ran for N us and did not glitch output DMA. Test Passed");
    end

    $finish;
  end

endmodule
