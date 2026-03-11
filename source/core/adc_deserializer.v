module adc_deserializer (
    
  input [27:0] adc_dat_i_flat,    // Flat: ch3[6:0](27:21) ... ch0[6:0](6:0)

  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk_i CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, FREQ_HZ 125000000" *)
  input [3:0] adc_clk_i_flat,     // group1_p(3), group1_n(2), group0_p(1), group0_n(0)
  input ref_clk_200mhz,
  input rst_n,
  input sys_clk,
    
// Exported clock for synchronization - Add attributes here
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk_out CLK" *)
  output adc_clk_out,            //Exported clock for synchronization
  output signed [13:0] adc_ch0,
  output signed [13:0] adc_ch1,
  output signed [13:0] adc_ch2,
  output signed [13:0] adc_ch3
);

wire adc_clk_in [1:0];
wire adc_clk [1:0];
    
  wire [6:0] adc_dat_in [3:0];
  wire [6:0] adc_dat_dly [3:0];
  wire [1:0] adc_dat_ddr [3:0][6:0];
  reg [13:0] adc_dat_raw [3:0];
  
  
  reg [13:0] adc_dat_t [3:0];
  
  // Synchronizer registers for CH2 and CH3 (clock domain crossing)
  (* ASYNC_REG = "TRUE" *) reg [13:0] adc_dat_sync1_ch2;
  (* ASYNC_REG = "TRUE" *) reg [13:0] adc_dat_sync2_ch2;
  (* ASYNC_REG = "TRUE" *) reg [13:0] adc_dat_sync1_ch3;
  (* ASYNC_REG = "TRUE" *) reg [13:0] adc_dat_sync2_ch3;

IBUFDS i_clk0 (.I(adc_clk_i_flat[1]), .IB(adc_clk_i_flat[0]), .O(adc_clk_in[0]));
IBUFDS i_clk1 (.I(adc_clk_i_flat[3]), .IB(adc_clk_i_flat[2]), .O(adc_clk_in[1]));
BUFG bufg0 (.I(adc_clk_in[0]), .O(adc_clk[0]));
BUFG bufg1 (.I(adc_clk_in[1]), .O(adc_clk[1]));

assign adc_clk_out = adc_clk[0];    

wire delay_ready;
IDELAYCTRL i_idelayctrl (
  .RDY(delay_ready),
  .REFCLK(ref_clk_200mhz),
   .RST(~rst_n)  // CRITICAL FIX: Use rst_n, not inverted ref_clk
);

genvar ch, bit;
  generate
    for (ch = 0; ch < 4; ch = ch + 1) begin : gen_adc
      assign adc_dat_in[ch] = adc_dat_i_flat[ch*7 +: 7];

      // Explicitly define which clock to use to avoid "non-constant" errors
      wire current_clk = (ch < 2) ? adc_clk[0] : adc_clk[1];

      for (bit = 0; bit < 7; bit = bit + 1) begin : gen_bits
		  
//previous version        
//        IDELAYE2 #(
//          .IDELAY_TYPE("FIXED")
//        ) i_delay (
//          .C(ref_clk_200mhz), // Fixed: used C instead of CLKIN
//          .REGRST(1'b0),
//          .LD(1'b0),
//          .IDATAIN(adc_dat_in[ch][bit]),
//          .DATAOUT(adc_dat_dly[ch][bit]),
//          .CE(1'b0),
//          .INC(1'b0),
//          .LDPIPEEN(1'b0),
//          .CNTVALUEIN(5'b0)
//        );
		IDELAYE2 #(
          .DELAY_SRC("IDATAIN"),           // Delay the IDATAIN signal
          .HIGH_PERFORMANCE_MODE("TRUE"),  // Reduced jitter
          .IDELAY_TYPE("VARIABLE"),        // CRITICAL: VARIABLE not FIXED!
          .IDELAY_VALUE(4),                // 4 tap delay (adjustable via CE/INC)
          .REFCLK_FREQUENCY(200.0),        // IDELAYCTRL frequency
          .SIGNAL_PATTERN("DATA")          // DATA not CLOCK
        ) i_delay (
          .CNTVALUEOUT(),                  // Not used in FIXED mode
          .DATAOUT(adc_dat_dly[ch][bit]),  // Delayed output
          .C(ref_clk_200mhz),              // Clock for dynamic control
          .CE(1'b0),                       // Not incrementing/decrementing
          .CINVCTRL(1'b0),                 // No clock inversion
          .CNTVALUEIN(5'h0),               // Not loading tap value
          .DATAIN(1'b0),                   // Not using DATAIN (using IDATAIN)
          .IDATAIN(adc_dat_in[ch][bit]),   // Input from IOB
          .INC(1'b0),                      // Not incrementing
          .LD(1'b0),                       // Not loading CNTVALUEIN
          .LDPIPEEN(1'b0),                 // Pipeline not enabled
          .REGRST(1'b0)                    // No reset
        );
		  
		  
        // IDDR: Convert LVDS DDR to 2-bit Parallel
        IDDR #(
          .DDR_CLK_EDGE("SAME_EDGE_PIPELINED")
        ) i_iddr (
          .Q1(adc_dat_ddr[ch][bit][0]),
          .Q2(adc_dat_ddr[ch][bit][1]),
          .C(current_clk),
          .CE(1'b1),
          .D(adc_dat_dly[ch][bit]),
          .R(1'b0),
          .S(1'b0)
        );
      end

      // Reconstruct 14-bit words
      always @(posedge current_clk or negedge rst_n) begin
        if (!rst_n) begin
          adc_dat_raw[ch] <= 14'd0;
        end else begin
          adc_dat_raw[ch] <= {
            ~adc_dat_ddr[ch][6][1], // INVERT MSB: Converts Offset Binary to Two's Complement
            adc_dat_ddr[ch][6][0],
            adc_dat_ddr[ch][5][1], adc_dat_ddr[ch][5][0],
            adc_dat_ddr[ch][4][1], adc_dat_ddr[ch][4][0],
            adc_dat_ddr[ch][3][1], adc_dat_ddr[ch][3][0],
            adc_dat_ddr[ch][2][1], adc_dat_ddr[ch][2][0],
            adc_dat_ddr[ch][1][1], adc_dat_ddr[ch][1][0],
            adc_dat_ddr[ch][0][1], adc_dat_ddr[ch][0][0]
          };
        end
      end
    end
  endgenerate


  // CH0 and CH1: Direct assignment (same clock domain)
  // CH2 and CH3: Dual-FF synchronizer (clock domain crossing from adc_clk[1] to adc_clk[0])
  // IMPORTANT: Timing constraints in .xdc file ensure this works reliably
  // Without constraints, synchronizer may fail due to metastability!	
  
  always @(posedge adc_clk[0] or negedge rst_n) begin
    if (!rst_n) begin
      // CH0 and CH1
      adc_dat_t[0] <= 14'd0;
      adc_dat_t[1] <= 14'd0;
      
      // CH2 and CH3 synchronizers
      adc_dat_sync1_ch2 <= 14'd0;
      adc_dat_sync2_ch2 <= 14'd0;
      adc_dat_t[2] <= 14'd0;
      
      adc_dat_sync1_ch3 <= 14'd0;
      adc_dat_sync2_ch3 <= 14'd0;
      adc_dat_t[3] <= 14'd0;
    end else begin
      // CH0 and CH1: Same clock domain - direct assignment
      adc_dat_t[0] <= adc_dat_raw[0];
      adc_dat_t[1] <= adc_dat_raw[1];
      
      // CH2: Clock domain crossing - dual-FF synchronizer
      // Stage 1: Capture from adc_clk[1] domain (may be metastable)
      adc_dat_sync1_ch2 <= adc_dat_raw[2];
      // Stage 2: Metastability should resolve here
      adc_dat_sync2_ch2 <= adc_dat_sync1_ch2;
      // Stage 3: Stable output to adc_clk[0] domain
      adc_dat_t[2] <= adc_dat_sync2_ch2;
		
      // CH3: Clock domain crossing - dual-FF synchronizer
      adc_dat_sync1_ch3 <= adc_dat_raw[3];
      adc_dat_sync2_ch3 <= adc_dat_sync1_ch3;
      adc_dat_t[3] <= adc_dat_sync2_ch3;
    end
  end

  assign adc_ch0 = adc_dat_t[0];
  assign adc_ch1 = adc_dat_t[1];
  assign adc_ch2 = adc_dat_t[2];
  assign adc_ch3 = adc_dat_t[3];

endmodule