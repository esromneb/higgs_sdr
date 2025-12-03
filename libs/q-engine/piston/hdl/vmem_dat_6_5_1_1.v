module vmem_dat_6_5_1_1
  #(parameter VMEM_SIZE = 4096,
    parameter VMEM0 = "vmem0.mif",
  parameter VMEM1 = "vmem1.mif",
  parameter VMEM2 = "vmem2.mif",
  parameter VMEM3 = "vmem3.mif",
  parameter VMEM4 = "vmem4.mif",
  parameter VMEM5 = "vmem5.mif",
  parameter VMEM6 = "vmem6.mif",
  parameter VMEM7 = "vmem7.mif",
  parameter VMEM8 = "vmem8.mif",
  parameter VMEM9 = "vmem9.mif",
  parameter VMEM10 = "vmem10.mif",
  parameter VMEM11 = "vmem11.mif",
  parameter VMEM12 = "vmem12.mif",
  parameter VMEM13 = "vmem13.mif",
  parameter VMEM14 = "vmem14.mif",
  parameter VMEM15 = "vmem15.mif",
  parameter VMEM16 = "vmem16.mif",
  parameter VMEM17 = "vmem17.mif",
  parameter VMEM18 = "vmem18.mif",
  parameter VMEM19 = "vmem19.mif",
  parameter VMEM20 = "vmem20.mif",
  parameter VMEM21 = "vmem21.mif",
  parameter VMEM22 = "vmem22.mif",
  parameter VMEM23 = "vmem23.mif",
  parameter VMEM24 = "vmem24.mif",
  parameter VMEM25 = "vmem25.mif",
  parameter VMEM26 = "vmem26.mif",
  parameter VMEM27 = "vmem27.mif",
  parameter VMEM28 = "vmem28.mif",
  parameter VMEM29 = "vmem29.mif",
  parameter VMEM30 = "vmem30.mif",
  parameter VMEM31 = "vmem31.mif",

  // how many slices (template: slices)
  parameter S = 16,

  // how many DMA (template: inputs)
  parameter D = 4,

  // how many extra address bits, corresponding to log2(# of dma)
  parameter EAB = 2,

  // address width of incoming DMA (template: iAddrWidth)
  parameter AW = 16,

  // address width of the slice, (template: oAddrWidth)
  parameter AS = 12,

  // dataWidth (template: dataWidth)
  parameter DW = 32
    )
(input wire [48:0]    t_idma_0_dat,
 input wire [48:0]   t_idma_1_dat,
 input wire [48:0]   t_idma_2_dat,
 input wire [48:0]   t_idma_3_dat,

 input wire [3:0]                          idma_valid,
 output wire [3:0]                         idma_ready,

 output wire [31:0]                    i_odma_0_dat,
 output wire [31:0]                    i_odma_1_dat,
 output wire [31:0]                    i_odma_2_dat,
 output wire [31:0]                    i_odma_3_dat,

 output wire [3:0]                         odma_valid,
 input wire [3:0]                          odma_ready,


 input wire [511:0]              t_ivs_dat,

 input wire [195:0] t_ka_dat,
 //exports
 input wire                                              tvs_valid,
 output wire                                             tvs_ready,

 output wire [511:0]             i_ovs_dat,
 //exports
 output wire                                             ivs_valid,
 input wire                                              ivs_ready,

 output wire [3:0]                     k_ctrl,

 input wire                                              clk, reset_n
 );


localparam SMO = S - 1;
localparam DMO = D - 1;
localparam DWMO = DW - 1;

// slice address width minus one
// the slice is already 4 bits less wide that the dma addresses (due to 16 slices)
localparam SAWMO = AS - 1; // 11

// how wide is the address that goes into the slice, this is -4 because of 16 slices, but we add the extra address bits
// (Extra Slice Address Width) Minus One = SAWMO + EAB
localparam ESAWMO = AS + EAB - 1; // 13

// pack width minus one, this is the width of the input data because data address and rw are all packed together
// DW + AW + 1 - 1
// template: (iAddrWidth + dataWidth) + 1 -1
// the +1 is for rw bit, the -1 is for "minus one"
localparam PWMO = DW + AW + 1 - 1; // 48

// after the input arbiter, we remove 4 bits from address due to slice, but now we are adding on 2 extra address bits
// we pack the address and data and r/w bits into one EB15, so that's why we need this calculation
// wide slice pack width minus one
// template: (not templated yet)
localparam SPW = DW + (EAB + AS) + 1;
localparam SPWMO = SPW - 1; // 46



 // Memory interface signals for 16 memory banks
 reg [ESAWMO:0]  n_mem_payload_addr[SMO:0];  // Next cycle address
 reg [31:0]  n_mem_payload_data[SMO:0];  // Next cycle data
 reg         n_mem_payload_we[SMO:0];     // Next cycle write enable
 reg         n_mem_valid[SMO:0];          // Next cycle valid
//  reg         n_mem_ready[15:0];          // Next cycle ready

// debug
`ifdef VERILATOR
reg         [31:0] arb_select_hex_0;
`endif

 // Registered versions of memory signals


 // now wires to make life easy
 wire [ESAWMO:0]  q_mem_payload_addr[15:0];
 wire [31:0]  q_mem_payload_data[15:0];
 wire         q_mem_payload_we[15:0];
 wire         q_mem_valid[15:0];
 wire         q_mem_ready[15:0];

 wire [ESAWMO:0] t1_mem_payload_addr[15:0];
 wire [31:0] t1_mem_payload_data[15:0];
 wire        t1_mem_payload_valid[15:0];
 wire        t1_mem_payload_ready[15:0];

 // Conflict detection matrix and ready signals
 reg [3:0]   n_ready_matrix[3:0];  // Matrix tracking conflicts between DMA channels
 reg         q_idma_ready[3:0];         // Consolidated ready per channel
 reg [3:0]   q_ready_matrix[3:0];  // Registered matrix
 reg         q_ready[3:0];         // Registered ready
 wire mem_bank_ready[3:0];

 // Loop variables for generating logic
 reg [31:0]  ii,jj,i,j,banki,dmai,bankj;
 genvar eb_i;

 // Unpacked arrays for DMA interface
 wire [31:0] idma_data[3:0];    // Input DMA data REMOVEME
 wire [15:0] idma_addr[3:0];    // Input DMA address REMOVEME
 wire        idma_we[3:0];      // Input DMA write enable REMOVEME
 wire [31:0] q_idma_data[3:0];
 wire [15:0] q_idma_addr[3:0];
 wire        q_idma_we[3:0];
 wire        q_idma_valid[3:0];

// debug: split signals out of the array for easier plotting in gtkwave
`ifdef VERILATOR
 wire [15:0] idma_addr_0 = idma_addr[0];
 wire [31:0] idma_data_0 = idma_data[0];
 wire idma_we_0 = idma_we[0];
 wire idma_valid_0 = idma_valid[0];
 wire idma_ready_0 = idma_ready[0];
 wire q_idma_ready0 = q_idma_ready[0];
 wire q_ready_0 = q_ready[0];
 wire q_idma_valid_0 = q_idma_valid[0];
 wire q_idma_we_0 = q_idma_we[0];
 wire n_mem_valid_0 = n_mem_valid[0];
//  wire [31:0] q_idma_data_0 = q_idma_data[0];

 wire [15:0] idma_addr_1 = idma_addr[1];
 wire [31:0] idma_data_1 = idma_data[1];
 wire idma_we_1 = idma_we[1];
 wire idma_valid_1 = idma_valid[1];
 wire idma_ready_1 = idma_ready[1];
 wire q_idma_ready1 = q_idma_ready[1];
 wire q_ready_1 = q_ready[1];
 wire q_idma_valid_1 = q_idma_valid[1];
 wire q_idma_we_1 = q_idma_we[1];
 wire n_mem_valid_1 = n_mem_valid[1];
//  wire [31:0] q_idma_data_1 = q_idma_data[1];

 wire [15:0] idma_addr_2 = idma_addr[2];
 wire [31:0] idma_data_2 = idma_data[2];
 wire idma_we_2 = idma_we[2];
 wire idma_valid_2 = idma_valid[2];
 wire idma_ready_2 = idma_ready[2];
 wire q_idma_ready2 = q_idma_ready[2];
 wire q_ready_2 = q_ready[2];
 wire q_idma_valid_2 = q_idma_valid[2];
 wire q_idma_we_2 = q_idma_we[2];
 wire n_mem_valid_2 = n_mem_valid[2];
//  wire [31:0] q_idma_data_2 = q_idma_data[2];


 wire [15:0] idma_addr_3 = idma_addr[3];
 wire [31:0] idma_data_3 = idma_data[3];
 wire idma_we_3 = idma_we[3];
 wire idma_valid_3 = idma_valid[3];
 wire idma_ready_3 = idma_ready[3];
 wire q_idma_ready3 = q_idma_ready[3];
 wire q_ready_3 = q_ready[3];
 wire q_idma_valid_3 = q_idma_valid[3];
 wire q_idma_we_3 = q_idma_we[3];
 wire n_mem_valid_3 = n_mem_valid[3];
//  wire [31:0] q_idma_data_3 = q_idma_data[3];
`endif

// Create packed array of t_idma signals
wire [48:0] t_idma_dat [3:0];
assign t_idma_dat[0] = t_idma_0_dat;
assign t_idma_dat[1] = t_idma_1_dat;
assign t_idma_dat[2] = t_idma_2_dat;
assign t_idma_dat[3] = t_idma_3_dat;

 // REMOVEME
 assign idma_addr[0]=t_idma_0_dat[47:32];
 assign idma_data[0]=t_idma_0_dat[31:0];
 assign idma_we[0]=t_idma_0_dat[48];

 assign idma_addr[1]=t_idma_1_dat[47:32];
 assign idma_data[1]=t_idma_1_dat[31:0];
 assign idma_we[1]=t_idma_1_dat[48];

 assign idma_addr[2]=t_idma_2_dat[47:32];
 assign idma_data[2]=t_idma_2_dat[31:0];
 assign idma_we[2]=t_idma_2_dat[48];

 assign idma_addr[3]=t_idma_3_dat[47:32];
 assign idma_data[3]=t_idma_3_dat[31:0];
 assign idma_we[3]=t_idma_3_dat[48];

 wire [48:0] eb_idma_t_data[3:0];
 wire eb_idma_t_valid[3:0];
 wire eb_idma_t_ready[3:0];
 wire [48:0] eb_idma_i_data[3:0];
 wire eb_idma_i_valid[3:0];
 wire eb_idma_i_ready[3:0];

 always @(posedge clk) begin
    for(dmai=0;dmai<4;dmai = dmai + 1) begin
      //  q_idma_addr[dmai]<=idma_addr[dmai];
      //  q_idma_data[dmai]<=idma_data[dmai];
      //  q_idma_we[dmai]<=idma_we[dmai];
      //  q_idma_valid[dmai]<=idma_valid[dmai];
       q_ready_matrix[dmai]<=n_ready_matrix[dmai];
        q_ready[dmai]<=q_idma_ready[dmai];

       // either q_idma_ready or q_ready
      //  eb_idma_t_ready <= q_idma_ready[dmai];
    end
 end



// loop and create eb buffers for the 4 dma inputs
// this replaces the previous registration using:
//      q_idma_data[dmai]<=idma_data[dmai];
// these are 1:1 with the DMA, any arbitration logic should
// deal with the output of this
 generate
 for(eb_i=0; eb_i<4; eb_i=eb_i+1) begin : eb_gen_idma
     // we don't need to pack t_idma_dat, b/c the signals already come into the top as packed
     assign eb_idma_t_data[eb_i] = t_idma_dat[eb_i];
     assign eb_idma_t_valid[eb_i] = idma_valid[eb_i];
     assign idma_ready[eb_i] = eb_idma_t_ready[eb_i];

     eb15 #(.DWIDTH(49)) eb_inst_idma (
         .t_data(eb_idma_t_data[eb_i]),    // din:  input
         .t_valid(eb_idma_t_valid[eb_i]),  // din:  input
         .t_ready(eb_idma_t_ready[eb_i]),  // din:  output
         .i_data(eb_idma_i_data[eb_i]),    // dout: output
         .i_valid(eb_idma_i_valid[eb_i]),  // dout: output
         .i_ready(eb_idma_i_ready[eb_i]),  // dout: input
         .clk(clk),
         .rstf(reset_n)
     );

     assign q_idma_data[eb_i] = eb_idma_i_data[eb_i][31:0];
     assign q_idma_addr[eb_i] = eb_idma_i_data[eb_i][47:32];
     assign q_idma_we[eb_i] = eb_idma_i_data[eb_i][48];
     assign q_idma_valid[eb_i] = eb_idma_i_valid[eb_i];
     assign eb_idma_i_ready[eb_i] = q_idma_ready[eb_i];

 end
 endgenerate

//  always @(posedge clk) begin
//     for(banki=0;banki<16;banki = banki + 1) begin
//       //  q_mem_ready[banki]<=n_mem_ready[banki];
//        q_mem_valid[banki]<=n_mem_valid[banki];
//        q_mem_payload_addr[banki]<=n_mem_payload_addr[banki];
//        q_mem_payload_data[banki]<=n_mem_payload_data[banki];
//        q_mem_payload_we[banki]<=n_mem_payload_we[banki];
//     end
//  end

 // after the input arbiter (This goes to the eb15 which then goes to the slice itself)
 wire [SPWMO:0] eb_t_data[SMO:0];
 wire eb_t_valid[SMO:0];
 wire eb_t_ready[SMO:0];
 wire [SPWMO:0] eb_i_data[SMO:0];
 wire eb_i_valid[SMO:0];
 wire eb_i_ready[SMO:0];

// debug
`ifdef VERILATOR
// per slice
wire eb_t_ready_0 = eb_t_ready[0];
wire eb_t_ready_1 = eb_t_ready[1];
`endif


 // Generate block with updated signal references

 generate
 // this EB is after the input arbitration, before the slice
 for(eb_i=0; eb_i<16; eb_i=eb_i+1) begin : eb_gen_slice
//      // Pack input signals into eb_t_data
     //                        1                       14                        32
     assign eb_t_data[eb_i] = {n_mem_payload_we[eb_i], n_mem_payload_addr[eb_i], n_mem_payload_data[eb_i]};
     assign eb_t_valid[eb_i] = n_mem_valid[eb_i];

     eb15 #(.DWIDTH(SPW)) eb_inst_slice_t1 (
         .t_data(eb_t_data[eb_i]),    // din:  input
         .t_valid(eb_t_valid[eb_i]),  // din:  input
         .t_ready(eb_t_ready[eb_i]),  // din:  output
         .i_data(eb_i_data[eb_i]),    // dout: output
         .i_valid(eb_i_valid[eb_i]),  // dout: output
         .i_ready(eb_i_ready[eb_i]),  // dout: input
         .clk(clk),
         .rstf(reset_n)
     );

   assign q_mem_payload_we[eb_i] = eb_i_data[eb_i][SPWMO];
   assign q_mem_payload_addr[eb_i] = eb_i_data[eb_i][ESAWMO+DW:DW]; //  13+32  : 32
   assign q_mem_payload_data[eb_i] = eb_i_data[eb_i][DWMO:0];  // 31:0
   assign q_mem_valid[eb_i] = eb_i_valid[eb_i];
   assign eb_i_ready[eb_i] = q_mem_ready[eb_i];

 end
 endgenerate


 // First declare the genvars
 genvar gbanki, gdmai;

 // Then declare the wire array
 wire [3:0] mem_select [15:0];  // [dma_channels][bank_number]

 // Use generate block with genvar loop counters
 generate
   for(gbanki=0; gbanki<16; gbanki=gbanki+1) begin : bank_loop
     for(gdmai=0; gdmai<4; gdmai=gdmai+1) begin : dma_loop
       assign mem_select[gbanki][gdmai] = (q_idma_addr[gdmai][3:0]==gbanki && q_idma_ready[gdmai] && q_idma_valid[gdmai]);
     end
   end
 endgenerate


// Add order tracking signals to vmem_arb_out_inst
reg [3:0] order_wr_en;
wire [3:0] order_ready;
reg [3:0] order_slice_index [3:0];

// Add order tracking registers
reg [3:0] order_wr_en_reg;
reg [3:0] order_slice_index_reg [3:0];

  // Core arbitration logic
  always @(*) begin
     // For each DMA channel i
     for(i=0;i<4;i = i + 1) begin
        // Check against every other channel j
        for(j=0;j<4;j = j + 1) begin
           if(j<i)
             // If channel j is trying to access same bank as channel i
             // and channel j is valid, then i cannot proceed
             n_ready_matrix[i][j]=(q_idma_addr[i][3:0]==q_idma_addr[j][3:0] && q_idma_valid[j])?0:1;
           else
             // No conflict check needed for j>=i
             n_ready_matrix[i][j]=1;
        end

        // Get target memory slice ready signal based on address
      //   wire target_ready = eb_t_ready[idma_addr[i][3:0]];

        // Channel i is ready only if:
        // 1. No conflicts with any other channel AND
        // 2. Target memory slice is ready
      // seems ok, but then eb_idma_t_ready is never read
      //   q_idma_ready[i] = (&n_ready_matrix[i]) & eb_t_ready[idma_addr[i][3:0]];
      //   q_idma_ready[i] = (&n_ready_matrix[i]) & eb_t_ready[idma_addr[i][3:0]] & eb_idma_t_ready[i];

      // seems less smart but why not work?
      //   q_idma_ready[i] = (&n_ready_matrix[i]) & eb_idma_t_ready[i];
      // don't compare with eb_t_ready[i] because that's a SLICE index

        q_idma_ready[i] = (&n_ready_matrix[i])
                          & eb_t_ready[q_idma_addr[i][3:0]]
                          & (q_idma_we[i] | order_ready[i]);
     end

     // Clear memory control signals
     for(ii=0;ii<16;ii= ii + 1) begin
        n_mem_valid[ii]=0;
        n_mem_payload_addr[ii]=0;
        n_mem_payload_data[ii]=0;
        n_mem_payload_we[ii]=0;
     end
     `ifdef VERILATOR
     // zero out debug signal
     arb_select_hex_0 = 32'h0;
     `endif

    // Clear order tracking signals
    order_wr_en_reg = 4'b0;
    for(i = 0; i < 4; i = i + 1) begin
        order_slice_index_reg[i] = 4'b0;
    end

  // Route DMA requests to appropriate memory bank
  // ii indexes memory banks, jj indexes DMA channels
  // this looks to see if the next dma write matches a bank (by looking at lower 4 bits = 16 banks)
  // when mem_select is good, we connect the dma to the slice here
  for(banki=0;banki<16;banki= banki + 1) begin
     for(dmai=0;dmai<4;dmai = dmai + 1) begin
        // If DMA channel dmai wants bank banki and is ready/valid
        // assign mem_select[banki][dmai] = (q_idma_addr[dmai][3:0]==banki && q_ready[dmai] && q_idma_valid[dmai]);
        if(mem_select[banki][dmai]) begin
             n_mem_valid[banki]=q_idma_valid[dmai];
             // load the bank that this read/write came from to the head of the address
             n_mem_payload_addr[banki]={dmai[1:0], q_idma_addr[dmai][15:4]};
             n_mem_payload_data[banki]=q_idma_data[dmai];
             n_mem_payload_we[banki]=q_idma_we[dmai];


            // For reads, record the order
            // Route DMA requests to appropriate memory bank
            // When we select a bank for a DMA read, record that order
            if (!q_idma_we[dmai]) begin
               order_wr_en_reg[dmai] = 1'b1;
               order_slice_index_reg[dmai] = banki[3:0];
            end

            `ifdef VERILATOR
            if(banki == 0) begin
                arb_select_hex_0[7:0] = dmai;
                arb_select_hex_0[15:8] = 8'h0;
                arb_select_hex_0[23:16] = banki;
            end
            `endif
        end


//            if(q_idma_ready[jj])
      end
   end

  end // always_comb

// Register the order tracking signals
always @(posedge clk) begin
    if (!reset_n) begin
        order_wr_en <= 4'b0;
        for(i = 0; i < 4; i = i + 1) begin
            order_slice_index[i] <= 4'b0;
        end
    end else begin
        order_wr_en <= order_wr_en_reg;
        for(i = 0; i < 4; i = i + 1) begin
            order_slice_index[i] <= order_slice_index_reg[i];
        end
    end
end

 wire [11:0] t_vs_payload_addr[15:0];
 wire [11:0] i_vs_payload_addr[15:0];
 wire [31:0] t_vs_payload_data[15:0];
 wire [31:0] i_vs_payload_data[15:0];
 wire vs_we;
 wire [3:0] s_k;

 assign s_k=t_ka_dat[195:192];
 assign vs_we=(tvs_valid && s_k<8)?1:0;

 assign t_vs_payload_addr[0]=t_ka_dat[11:0];
 assign t_vs_payload_data[0]=t_ivs_dat[31:0];

 assign t_vs_payload_addr[1]=t_ka_dat[23:12];
 assign t_vs_payload_data[1]=t_ivs_dat[63:32];

 assign t_vs_payload_addr[2]=t_ka_dat[35:24];
 assign t_vs_payload_data[2]=t_ivs_dat[95:64];

 assign t_vs_payload_addr[3]=t_ka_dat[47:36];
 assign t_vs_payload_data[3]=t_ivs_dat[127:96];

 assign t_vs_payload_addr[4]=t_ka_dat[59:48];
 assign t_vs_payload_data[4]=t_ivs_dat[159:128];

 assign t_vs_payload_addr[5]=t_ka_dat[71:60];
 assign t_vs_payload_data[5]=t_ivs_dat[191:160];

 assign t_vs_payload_addr[6]=t_ka_dat[83:72];
 assign t_vs_payload_data[6]=t_ivs_dat[223:192];

 assign t_vs_payload_addr[7]=t_ka_dat[95:84];
 assign t_vs_payload_data[7]=t_ivs_dat[255:224];

 assign t_vs_payload_addr[8]=t_ka_dat[107:96];
 assign t_vs_payload_data[8]=t_ivs_dat[287:256];

 assign t_vs_payload_addr[9]=t_ka_dat[119:108];
 assign t_vs_payload_data[9]=t_ivs_dat[319:288];

 assign t_vs_payload_addr[10]=t_ka_dat[131:120];
 assign t_vs_payload_data[10]=t_ivs_dat[351:320];

 assign t_vs_payload_addr[11]=t_ka_dat[143:132];
 assign t_vs_payload_data[11]=t_ivs_dat[383:352];

 assign t_vs_payload_addr[12]=t_ka_dat[155:144];
 assign t_vs_payload_data[12]=t_ivs_dat[415:384];

 assign t_vs_payload_addr[13]=t_ka_dat[167:156];
 assign t_vs_payload_data[13]=t_ivs_dat[447:416];

 assign t_vs_payload_addr[14]=t_ka_dat[179:168];
 assign t_vs_payload_data[14]=t_ivs_dat[479:448];

 assign t_vs_payload_addr[15]=t_ka_dat[191:180];
 assign t_vs_payload_data[15]=t_ivs_dat[511:480];

 assign k_ctrl=s_k;


// Add new wires for t0 elastic buffer connections
wire [44:0] eb_t0_t_data[15:0];  // 1 we + 12 addr + 32 data = 45 bits
wire eb_t0_t_valid[15:0];
wire eb_t0_t_ready[15:0];
wire [44:0] eb_t0_i_data[15:0];
wire eb_t0_i_valid[15:0];
wire eb_t0_i_ready[15:0];

// Generate eb15 instances for t0 port
genvar t0_slicei;
generate
for(t0_slicei=0; t0_slicei<16; t0_slicei=t0_slicei+1) begin : gen_t0_eb
    // Pack input signals into eb_t0_t_data including vs_we
    assign eb_t0_t_data[t0_slicei] = {vs_we, t_vs_payload_addr[t0_slicei], t_vs_payload_data[t0_slicei]};
    assign eb_t0_t_valid[t0_slicei] = tvs_valid;

    assign eb_t0_i_data[t0_slicei] = eb_t0_t_data[t0_slicei];
    assign eb_t0_i_valid[t0_slicei] = eb_t0_t_valid[t0_slicei];
    assign eb_t0_t_ready[t0_slicei] = eb_t0_i_ready[t0_slicei];
    // eb15 #(.DWIDTH(45)) eb_inst_slice_t0 (
    //     .t_data(eb_t0_t_data[slicei]),
    //     .t_valid(eb_t0_t_valid[slicei]),
    //     .t_ready(eb_t0_t_ready[slicei]),
    //     .i_data(eb_t0_i_data[slicei]),
    //     .i_valid(eb_t0_i_valid[slicei]),
    //     .i_ready(eb_t0_i_ready[slicei]),
    //     .clk(clk),
    //     .rstf(reset_n)
    // );
end
endgenerate

// Update tvs_ready to use eb15 ready signal
assign tvs_ready = eb_t0_t_ready[0] & eb_t0_t_ready[1] & eb_t0_t_ready[2] & eb_t0_t_ready[3] &
                   eb_t0_t_ready[4] & eb_t0_t_ready[5] & eb_t0_t_ready[6] & eb_t0_t_ready[7] &
                   eb_t0_t_ready[8] & eb_t0_t_ready[9] & eb_t0_t_ready[10] & eb_t0_t_ready[11] &
                   eb_t0_t_ready[12] & eb_t0_t_ready[13] & eb_t0_t_ready[14] & eb_t0_t_ready[15];

//[511:0];

// debug: split signals out of the array for easier plotting in gtkwave
`ifdef VERILATOR
// slice addresses, not dma
wire q_mem_valid_0 = q_mem_valid[0];
wire q_mem_ready_0 = q_mem_ready[0];

// slice addresses, not dma
// wire t_mem_valid_0 = t_mem_valid[0];
// wire t_mem_valid_1 = t_mem_valid[1];
`endif


// upper 2 bits of the address given to the slice, which actually encodes the DMA that it came in on
// Must be an unpacked array
wire [1:0] t1_mem_payload_addr_extra_array [15:0];

genvar slicei;
generate
  for(slicei=0; slicei<16; slicei=slicei+1) begin : gen_addr_extra
   assign t1_mem_payload_addr_extra_array[slicei] = t1_mem_payload_addr[slicei][ESAWMO:AS]; // [13:12]
  end
endgenerate

wire [127:0] arb_odma_out;

// reads come into the 16 memory slices
// when the read is ready, it comes out here
// the top 2 bits of the read address encode which output DMA this is destined for
// this arbiter routes all these reads out to the correct place
`ifdef VMEM_DAT_ARB_OUT_1_1
vmem_dat_arb_out_spinal_wrapper
`else
vmem_dat_arb_out_1_0
`endif
vmem_arb_out_inst (
    .clk(clk),
    .rst_n(reset_n),

    // Connect all 16 memory slice inputs
    .in_valid({
        t1_mem_payload_valid[15],
        t1_mem_payload_valid[14],
        t1_mem_payload_valid[13],
        t1_mem_payload_valid[12],
        t1_mem_payload_valid[11],
        t1_mem_payload_valid[10],
        t1_mem_payload_valid[9],
        t1_mem_payload_valid[8],
        t1_mem_payload_valid[7],
        t1_mem_payload_valid[6],
        t1_mem_payload_valid[5],
        t1_mem_payload_valid[4],
        t1_mem_payload_valid[3],
        t1_mem_payload_valid[2],
        t1_mem_payload_valid[1],
        t1_mem_payload_valid[0]
    }),
    .in_ready({
        t1_mem_payload_ready[15],
        t1_mem_payload_ready[14],
        t1_mem_payload_ready[13],
        t1_mem_payload_ready[12],
        t1_mem_payload_ready[11],
        t1_mem_payload_ready[10],
        t1_mem_payload_ready[9],
        t1_mem_payload_ready[8],
        t1_mem_payload_ready[7],
        t1_mem_payload_ready[6],
        t1_mem_payload_ready[5],
        t1_mem_payload_ready[4],
        t1_mem_payload_ready[3],
        t1_mem_payload_ready[2],
        t1_mem_payload_ready[1],
        t1_mem_payload_ready[0]
    }),
    .in_data({
        t1_mem_payload_data[15], t1_mem_payload_data[14],
        t1_mem_payload_data[13], t1_mem_payload_data[12],
        t1_mem_payload_data[11], t1_mem_payload_data[10],
        t1_mem_payload_data[9],  t1_mem_payload_data[8],
        t1_mem_payload_data[7],  t1_mem_payload_data[6],
        t1_mem_payload_data[5],  t1_mem_payload_data[4],
        t1_mem_payload_data[3],  t1_mem_payload_data[2],
        t1_mem_payload_data[1],  t1_mem_payload_data[0]
    }),

    // Assign each array element individually
    .in_out_num({
        t1_mem_payload_addr_extra_array[15], t1_mem_payload_addr_extra_array[14],
        t1_mem_payload_addr_extra_array[13], t1_mem_payload_addr_extra_array[12],
        t1_mem_payload_addr_extra_array[11], t1_mem_payload_addr_extra_array[10],
        t1_mem_payload_addr_extra_array[9],  t1_mem_payload_addr_extra_array[8],
        t1_mem_payload_addr_extra_array[7],  t1_mem_payload_addr_extra_array[6],
        t1_mem_payload_addr_extra_array[5],  t1_mem_payload_addr_extra_array[4],
        t1_mem_payload_addr_extra_array[3],  t1_mem_payload_addr_extra_array[2],
        t1_mem_payload_addr_extra_array[1],  t1_mem_payload_addr_extra_array[0]
    }),

    // Add new order tracking signals
    .order_wr_en(order_wr_en),
    .order_ready(order_ready),
    .order_slice_index({
        order_slice_index[3], order_slice_index[2],
        order_slice_index[1], order_slice_index[0]
    }),

    // Connect the 4 outputs
    .out_valid(odma_valid),
    .out_ready(odma_ready),
    .out_data(arb_odma_out)
);

assign i_odma_0_dat = arb_odma_out[31:0];
assign i_odma_1_dat = arb_odma_out[63:32];
assign i_odma_2_dat = arb_odma_out[95:64];
assign i_odma_3_dat = arb_odma_out[127:96];




`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM0),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM0),.DEPTH(VMEM_SIZE))
`endif
mem_slice_0
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[0][43:32]),
 .t0_data(eb_t0_i_data[0][31:0]),
 .t0_we(eb_t0_i_data[0][44]),
 .t0_valid(eb_t0_i_valid[0]),
 .t0_ready(eb_t0_i_ready[0]),


 .i0_addr(i_vs_payload_addr[0]),
 .i0_data(i_ovs_dat[31:0]),

 .i0_valid(ivs_valid),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[0]),
 .t1_data(q_mem_payload_data[0]),
 .t1_we(q_mem_payload_we[0]),
 .t1_valid(q_mem_valid[0]),
 .t1_ready(q_mem_ready[0]),
 .i1_addr(t1_mem_payload_addr[0]),
 .i1_data(t1_mem_payload_data[0]),
 .i1_valid(t1_mem_payload_valid[0]),
 .i1_ready(t1_mem_payload_ready[0])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM1),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM1),.DEPTH(VMEM_SIZE))
`endif
mem_slice_1
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[1][43:32]),
 .t0_data(eb_t0_i_data[1][31:0]),
 .t0_we(eb_t0_i_data[1][44]),
 .t0_valid(eb_t0_i_valid[1]),
 .t0_ready(eb_t0_i_ready[1]),


 .i0_addr(i_vs_payload_addr[1]),
 .i0_data(i_ovs_dat[63:32]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[1]),
 .t1_data(q_mem_payload_data[1]),
 .t1_we(q_mem_payload_we[1]),
 .t1_valid(q_mem_valid[1]),
 .t1_ready(q_mem_ready[1]),
 .i1_addr(t1_mem_payload_addr[1]),
 .i1_data(t1_mem_payload_data[1]),
 .i1_valid(t1_mem_payload_valid[1]),
 .i1_ready(t1_mem_payload_ready[1])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM2),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM2),.DEPTH(VMEM_SIZE))
`endif
mem_slice_2
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[2][43:32]),
 .t0_data(eb_t0_i_data[2][31:0]),
 .t0_we(eb_t0_i_data[2][44]),
 .t0_valid(eb_t0_i_valid[2]),
 .t0_ready(eb_t0_i_ready[2]),


 .i0_addr(i_vs_payload_addr[2]),
 .i0_data(i_ovs_dat[95:64]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[2]),
 .t1_data(q_mem_payload_data[2]),
 .t1_we(q_mem_payload_we[2]),
 .t1_valid(q_mem_valid[2]),
 .t1_ready(q_mem_ready[2]),
 .i1_addr(t1_mem_payload_addr[2]),
 .i1_data(t1_mem_payload_data[2]),
 .i1_valid(t1_mem_payload_valid[2]),
 .i1_ready(t1_mem_payload_ready[2])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM3),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM3),.DEPTH(VMEM_SIZE))
`endif
mem_slice_3
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[3][43:32]),
 .t0_data(eb_t0_i_data[3][31:0]),
 .t0_we(eb_t0_i_data[3][44]),
 .t0_valid(eb_t0_i_valid[3]),
 .t0_ready(eb_t0_i_ready[3]),


 .i0_addr(i_vs_payload_addr[3]),
 .i0_data(i_ovs_dat[127:96]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[3]),
 .t1_data(q_mem_payload_data[3]),
 .t1_we(q_mem_payload_we[3]),
 .t1_valid(q_mem_valid[3]),
 .t1_ready(q_mem_ready[3]),
 .i1_addr(t1_mem_payload_addr[3]),
 .i1_data(t1_mem_payload_data[3]),
 .i1_valid(t1_mem_payload_valid[3]),
 .i1_ready(t1_mem_payload_ready[3])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM4),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM4),.DEPTH(VMEM_SIZE))
`endif
mem_slice_4
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[4][43:32]),
 .t0_data(eb_t0_i_data[4][31:0]),
 .t0_we(eb_t0_i_data[4][44]),
 .t0_valid(eb_t0_i_valid[4]),
 .t0_ready(eb_t0_i_ready[4]),


 .i0_addr(i_vs_payload_addr[4]),
 .i0_data(i_ovs_dat[159:128]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[4]),
 .t1_data(q_mem_payload_data[4]),
 .t1_we(q_mem_payload_we[4]),
 .t1_valid(q_mem_valid[4]),
 .t1_ready(q_mem_ready[4]),
 .i1_addr(t1_mem_payload_addr[4]),
 .i1_data(t1_mem_payload_data[4]),
 .i1_valid(t1_mem_payload_valid[4]),
 .i1_ready(t1_mem_payload_ready[4])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM5),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM5),.DEPTH(VMEM_SIZE))
`endif
mem_slice_5
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[5][43:32]),
 .t0_data(eb_t0_i_data[5][31:0]),
 .t0_we(eb_t0_i_data[5][44]),
 .t0_valid(eb_t0_i_valid[5]),
 .t0_ready(eb_t0_i_ready[5]),


 .i0_addr(i_vs_payload_addr[5]),
 .i0_data(i_ovs_dat[191:160]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[5]),
 .t1_data(q_mem_payload_data[5]),
 .t1_we(q_mem_payload_we[5]),
 .t1_valid(q_mem_valid[5]),
 .t1_ready(q_mem_ready[5]),
 .i1_addr(t1_mem_payload_addr[5]),
 .i1_data(t1_mem_payload_data[5]),
 .i1_valid(t1_mem_payload_valid[5]),
 .i1_ready(t1_mem_payload_ready[5])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM6),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM6),.DEPTH(VMEM_SIZE))
`endif
mem_slice_6
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[6][43:32]),
 .t0_data(eb_t0_i_data[6][31:0]),
 .t0_we(eb_t0_i_data[6][44]),
 .t0_valid(eb_t0_i_valid[6]),
 .t0_ready(eb_t0_i_ready[6]),


 .i0_addr(i_vs_payload_addr[6]),
 .i0_data(i_ovs_dat[223:192]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[6]),
 .t1_data(q_mem_payload_data[6]),
 .t1_we(q_mem_payload_we[6]),
 .t1_valid(q_mem_valid[6]),
 .t1_ready(q_mem_ready[6]),
 .i1_addr(t1_mem_payload_addr[6]),
 .i1_data(t1_mem_payload_data[6]),
 .i1_valid(t1_mem_payload_valid[6]),
 .i1_ready(t1_mem_payload_ready[6])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM7),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM7),.DEPTH(VMEM_SIZE))
`endif
mem_slice_7
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[7][43:32]),
 .t0_data(eb_t0_i_data[7][31:0]),
 .t0_we(eb_t0_i_data[7][44]),
 .t0_valid(eb_t0_i_valid[7]),
 .t0_ready(eb_t0_i_ready[7]),


 .i0_addr(i_vs_payload_addr[7]),
 .i0_data(i_ovs_dat[255:224]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[7]),
 .t1_data(q_mem_payload_data[7]),
 .t1_we(q_mem_payload_we[7]),
 .t1_valid(q_mem_valid[7]),
 .t1_ready(q_mem_ready[7]),
 .i1_addr(t1_mem_payload_addr[7]),
 .i1_data(t1_mem_payload_data[7]),
 .i1_valid(t1_mem_payload_valid[7]),
 .i1_ready(t1_mem_payload_ready[7])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM8),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM8),.DEPTH(VMEM_SIZE))
`endif
mem_slice_8
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[8][43:32]),
 .t0_data(eb_t0_i_data[8][31:0]),
 .t0_we(eb_t0_i_data[8][44]),
 .t0_valid(eb_t0_i_valid[8]),
 .t0_ready(eb_t0_i_ready[8]),


 .i0_addr(i_vs_payload_addr[8]),
 .i0_data(i_ovs_dat[287:256]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[8]),
 .t1_data(q_mem_payload_data[8]),
 .t1_we(q_mem_payload_we[8]),
 .t1_valid(q_mem_valid[8]),
 .t1_ready(q_mem_ready[8]),
 .i1_addr(t1_mem_payload_addr[8]),
 .i1_data(t1_mem_payload_data[8]),
 .i1_valid(t1_mem_payload_valid[8]),
 .i1_ready(t1_mem_payload_ready[8])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM9),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM9),.DEPTH(VMEM_SIZE))
`endif
mem_slice_9
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[9][43:32]),
 .t0_data(eb_t0_i_data[9][31:0]),
 .t0_we(eb_t0_i_data[9][44]),
 .t0_valid(eb_t0_i_valid[9]),
 .t0_ready(eb_t0_i_ready[9]),


 .i0_addr(i_vs_payload_addr[9]),
 .i0_data(i_ovs_dat[319:288]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[9]),
 .t1_data(q_mem_payload_data[9]),
 .t1_we(q_mem_payload_we[9]),
 .t1_valid(q_mem_valid[9]),
 .t1_ready(q_mem_ready[9]),
 .i1_addr(t1_mem_payload_addr[9]),
 .i1_data(t1_mem_payload_data[9]),
 .i1_valid(t1_mem_payload_valid[9]),
 .i1_ready(t1_mem_payload_ready[9])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM10),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM10),.DEPTH(VMEM_SIZE))
`endif
mem_slice_10
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[10][43:32]),
 .t0_data(eb_t0_i_data[10][31:0]),
 .t0_we(eb_t0_i_data[10][44]),
 .t0_valid(eb_t0_i_valid[10]),
 .t0_ready(eb_t0_i_ready[10]),


 .i0_addr(i_vs_payload_addr[10]),
 .i0_data(i_ovs_dat[351:320]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[10]),
 .t1_data(q_mem_payload_data[10]),
 .t1_we(q_mem_payload_we[10]),
 .t1_valid(q_mem_valid[10]),
 .t1_ready(q_mem_ready[10]),
 .i1_addr(t1_mem_payload_addr[10]),
 .i1_data(t1_mem_payload_data[10]),
 .i1_valid(t1_mem_payload_valid[10]),
 .i1_ready(t1_mem_payload_ready[10])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM11),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM11),.DEPTH(VMEM_SIZE))
`endif
mem_slice_11
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[11][43:32]),
 .t0_data(eb_t0_i_data[11][31:0]),
 .t0_we(eb_t0_i_data[11][44]),
 .t0_valid(eb_t0_i_valid[11]),
 .t0_ready(eb_t0_i_ready[11]),


 .i0_addr(i_vs_payload_addr[11]),
 .i0_data(i_ovs_dat[383:352]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[11]),
 .t1_data(q_mem_payload_data[11]),
 .t1_we(q_mem_payload_we[11]),
 .t1_valid(q_mem_valid[11]),
 .t1_ready(q_mem_ready[11]),
 .i1_addr(t1_mem_payload_addr[11]),
 .i1_data(t1_mem_payload_data[11]),
 .i1_valid(t1_mem_payload_valid[11]),
 .i1_ready(t1_mem_payload_ready[11])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM12),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM12),.DEPTH(VMEM_SIZE))
`endif
mem_slice_12
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[12][43:32]),
 .t0_data(eb_t0_i_data[12][31:0]),
 .t0_we(eb_t0_i_data[12][44]),
 .t0_valid(eb_t0_i_valid[12]),
 .t0_ready(eb_t0_i_ready[12]),


 .i0_addr(i_vs_payload_addr[12]),
 .i0_data(i_ovs_dat[415:384]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[12]),
 .t1_data(q_mem_payload_data[12]),
 .t1_we(q_mem_payload_we[12]),
 .t1_valid(q_mem_valid[12]),
 .t1_ready(q_mem_ready[12]),
 .i1_addr(t1_mem_payload_addr[12]),
 .i1_data(t1_mem_payload_data[12]),
 .i1_valid(t1_mem_payload_valid[12]),
 .i1_ready(t1_mem_payload_ready[12])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM13),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM13),.DEPTH(VMEM_SIZE))
`endif
mem_slice_13
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[13][43:32]),
 .t0_data(eb_t0_i_data[13][31:0]),
 .t0_we(eb_t0_i_data[13][44]),
 .t0_valid(eb_t0_i_valid[13]),
 .t0_ready(eb_t0_i_ready[13]),


 .i0_addr(i_vs_payload_addr[13]),
 .i0_data(i_ovs_dat[447:416]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[13]),
 .t1_data(q_mem_payload_data[13]),
 .t1_we(q_mem_payload_we[13]),
 .t1_valid(q_mem_valid[13]),
 .t1_ready(q_mem_ready[13]),
 .i1_addr(t1_mem_payload_addr[13]),
 .i1_data(t1_mem_payload_data[13]),
 .i1_valid(t1_mem_payload_valid[13]),
 .i1_ready(t1_mem_payload_ready[13])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM14),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM14),.DEPTH(VMEM_SIZE))
`endif
mem_slice_14
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[14][43:32]),
 .t0_data(eb_t0_i_data[14][31:0]),
 .t0_we(eb_t0_i_data[14][44]),
 .t0_valid(eb_t0_i_valid[14]),
 .t0_ready(eb_t0_i_ready[14]),


 .i0_addr(i_vs_payload_addr[14]),
 .i0_data(i_ovs_dat[479:448]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[14]),
 .t1_data(q_mem_payload_data[14]),
 .t1_we(q_mem_payload_we[14]),
 .t1_valid(q_mem_valid[14]),
 .t1_ready(q_mem_ready[14]),
 .i1_addr(t1_mem_payload_addr[14]),
 .i1_data(t1_mem_payload_data[14]),
 .i1_valid(t1_mem_payload_valid[14]),
 .i1_ready(t1_mem_payload_ready[14])
 );

`ifdef MEMORY_SLICE_1_1
memory_slice_1_1 #(.MEMINIT(VMEM15),.DEPTH(VMEM_SIZE))
`else
memory_slice #(.MEMINIT(VMEM15),.DEPTH(VMEM_SIZE))
`endif
mem_slice_15
(.clk(clk),
 .reset_n(reset_n),
 //port 0
 .t0_addr(eb_t0_i_data[15][43:32]),
 .t0_data(eb_t0_i_data[15][31:0]),
 .t0_we(eb_t0_i_data[15][44]),
 .t0_valid(eb_t0_i_valid[15]),
 .t0_ready(eb_t0_i_ready[15]),


 .i0_addr(i_vs_payload_addr[15]),
 .i0_data(i_ovs_dat[511:480]),

 .i0_valid(),


 .i0_ready(ivs_ready),
 //port 1
 .t1_addr(q_mem_payload_addr[15]),
 .t1_data(q_mem_payload_data[15]),
 .t1_we(q_mem_payload_we[15]),
 .t1_valid(q_mem_valid[15]),
 .t1_ready(q_mem_ready[15]),
 .i1_addr(t1_mem_payload_addr[15]),
 .i1_data(t1_mem_payload_data[15]),
 .i1_valid(t1_mem_payload_valid[15]),
 .i1_ready(t1_mem_payload_ready[15])
 );



endmodule
