`timescale 1ns / 1ps

module freq_counter (
  input clk,                    // ADC clock (approx 125MHz)
  input rst_n,
  input signed [13:0] adc_ch0,
  input signed [13:0] adc_ch1,
  input signed [13:0] adc_ch2,
  input signed [13:0] adc_ch3,
  input [13:0] threshold0,          
  input [13:0] threshold1,          
  input [13:0] threshold2,          
  input [13:0] threshold3,          
	output reg [27:0] freq_ch0,
	output reg [27:0] freq_ch1,
	output reg [27:0] freq_ch2,
	output reg [27:0] freq_ch3
);

  // Group inputs for easier indexing in generate block
  wire signed [13:0] adcs [0:3];
  assign adcs[0] = adc_ch0;
  assign adcs[1] = adc_ch1;
  assign adcs[2] = adc_ch2;
  assign adcs[3] = adc_ch3;

  wire [13:0] thresholds [0:3];
  assign thresholds[0] = threshold0;
  assign thresholds[1] = threshold1;
  assign thresholds[2] = threshold2;
  assign thresholds[3] = threshold3;

  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : CH_GEN
      reg state_armed;
		reg [27:0] counter;
		reg [27:0] timer;
		reg [27:0] freq_out;
      
      // Independent hysteresis calculation for each channel  was sd8
		wire signed [13:0] h_upper = $signed({1'b0, thresholds[i]}) + 14'sd32;
		wire signed [13:0] h_lower = $signed({1'b0, thresholds[i]}) - 14'sd32;

      always @(posedge clk) begin
        if (!rst_n) begin
          counter <= 0;
          timer <= 0;
          freq_out <= 0;
          state_armed <= 0;
        end else begin
          // Hysteresis Logic
		  if (adcs[i] > h_upper && !state_armed) begin
            state_armed <= 1;
			counter <= counter + 1;  
          end else if (adcs[i] < h_lower) begin
            state_armed <= 0;
          end

          // 1-Second Timer (125,000,000 cycles @ 125MHz)
          if (timer >= 125000000) begin
            freq_out <= counter;
            counter <= 0;
            timer <= 0;
          end else begin
            timer <= timer + 1;
          end
        end
      end

      // Mapping internal freq_out to specific output ports
      always @(*) begin
        case(i)
          0: freq_ch0 = freq_out;
          1: freq_ch1 = freq_out;
          2: freq_ch2 = freq_out;
          3: freq_ch3 = freq_out;
        endcase
      end
    end
  endgenerate

endmodule