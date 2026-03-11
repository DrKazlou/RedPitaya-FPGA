`timescale 1ns / 1ps
module comparator (
    input clk,
    input signed [13:0] adc_data,
    input signed [13:0] threshold,
    output reg hit
);
    reg state_armed;
    // Hysteresis is important to prevent multiple hits on a noisy edge
    wire signed [13:0] h_upper = threshold + 14'sd8;
    wire signed [13:0] h_lower = threshold - 14'sd8;

    always @(posedge clk) begin
        hit <= 0;
        if (adc_data > h_upper && !state_armed) begin
            state_armed <= 1;
            hit <= 1; // Pulse high for exactly 1 cycle
        end else if (adc_data < h_lower) begin
            state_armed <= 0;
        end
    end
endmodule
