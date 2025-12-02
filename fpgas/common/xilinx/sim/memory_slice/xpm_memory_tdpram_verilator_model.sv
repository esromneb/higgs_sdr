// A substitute, used only by Verilator, for Xilinx's `xpm_memory_tdpram`
// simulation model.
//
// Installed Verilator (4.016) cannot parse the vendor
// `xpm_memory.sv` (SystemVerilog assertions, `$rose`, etc.), so it cannot run
// `memory_slice_xilinx.v` unmodified.  This file provides a drop-in module
// with the identical parameter and port list, but it only implements the
// exact configuration `memory_slice_xilinx.v` actually instantiates:
// common clock, write-first on both ports, one-cycle read latency,
// `regcea`/`regceb` tied high, no ECC, and no reset/sleep support.  It is not
// a general-purpose XPM replacement.
//
// The modeled behavior was captured empirically from the real
// `xpm_memory_tdpram` under XSIM (see
// `fpgas/common/xilinx/sim/memory_slice/README.md`):
//   * `ena`/`enb` low holds the previous output register value.
//   * A write with `ena`/`enb` high shows the new data at the same one-cycle
//     latency as a read (write-first).
//   * Same-address, same-cycle accesses from the two ports where at least one
//     is a write produce an indeterminate ('x) result on the real primitive;
//     this model reproduces that only incidentally, and the parity test
//     deliberately never drives that combination.
module xpm_memory_tdpram #(
    parameter integer ADDR_WIDTH_A = 6,
    parameter integer ADDR_WIDTH_B = 6,
    parameter integer AUTO_SLEEP_TIME = 0,
    parameter integer BYTE_WRITE_WIDTH_A = 32,
    parameter integer BYTE_WRITE_WIDTH_B = 32,
    parameter CLOCKING_MODE = "common_clock",
    parameter ECC_MODE = "no_ecc",
    parameter MEMORY_INIT_FILE = "none",
    parameter MEMORY_INIT_PARAM = "0",
    parameter MEMORY_OPTIMIZATION = "true",
    parameter MEMORY_PRIMITIVE = "block",
    parameter integer MEMORY_SIZE = 2048,
    parameter integer MESSAGE_CONTROL = 0,
    parameter integer READ_DATA_WIDTH_A = 32,
    parameter integer READ_DATA_WIDTH_B = 32,
    parameter integer READ_LATENCY_A = 1,
    parameter integer READ_LATENCY_B = 1,
    parameter READ_RESET_VALUE_A = "0",
    parameter READ_RESET_VALUE_B = "0",
    parameter RST_MODE_A = "SYNC",
    parameter RST_MODE_B = "SYNC",
    parameter integer USE_EMBEDDED_CONSTRAINT = 0,
    parameter integer USE_MEM_INIT = 0,
    parameter WAKEUP_TIME = "disable_sleep",
    parameter integer WRITE_DATA_WIDTH_A = 32,
    parameter integer WRITE_DATA_WIDTH_B = 32,
    parameter WRITE_MODE_A = "write_first",
    parameter WRITE_MODE_B = "write_first"
) (
    input wire clka,
    input wire clkb,
    input wire [ADDR_WIDTH_A-1:0] addra,
    input wire [ADDR_WIDTH_B-1:0] addrb,
    input wire [WRITE_DATA_WIDTH_A-1:0] dina,
    input wire [WRITE_DATA_WIDTH_B-1:0] dinb,
    output reg [READ_DATA_WIDTH_A-1:0] douta,
    output reg [READ_DATA_WIDTH_B-1:0] doutb,
    input wire ena,
    input wire enb,
    input wire injectdbiterra,
    input wire injectdbiterrb,
    input wire injectsbiterra,
    input wire injectsbiterrb,
    input wire regcea,
    input wire regceb,
    input wire rsta,
    input wire rstb,
    input wire sleep,
    input wire wea,
    input wire web
);

    localparam integer DEPTH = MEMORY_SIZE / WRITE_DATA_WIDTH_A;

    reg [WRITE_DATA_WIDTH_A-1:0] mem[0:DEPTH-1];

    always @(posedge clka) begin
        if (ena) begin
            if (wea) begin
                mem[addra] <= dina;
                douta <= dina;
            end else begin
                douta <= mem[addra];
            end
        end
    end

    always @(posedge clkb) begin
        if (enb) begin
            if (web) begin
                mem[addrb] <= dinb;
                doutb <= dinb;
            end else begin
                doutb <= mem[addrb];
            end
        end
    end

endmodule
