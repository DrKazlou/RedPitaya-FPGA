`timescale 1ns / 1ps

module threshold_led #(
  parameter signed THRESHOLD = 100,
  parameter integer FLASH_CYCLES = 250000,     // ~2 ms flash
  parameter integer HOLDOFF_CYCLES = 6250000  // ~30 ms hold-off
)(
  input clk,
  input rst_n,
  input signed [13:0] adc_ch0,
  input signed [13:0] adc_ch1,
  input signed [13:0] adc_ch2,
  input signed [13:0] adc_ch3,
  output [7:0] led_out        // LED3 = ch3, LED2 = ch2, LED1 = ch1, LED0 = ch0
);


// Channel 0
reg led_active_ch0 = 0;
reg holdoff_active_ch0 = 0;
reg [31:0] counter_ch0 = 0;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    led_active_ch0 <= 0;
    holdoff_active_ch0 <= 0;
    counter_ch0 <= 0;
  end else begin
	  if (adc_ch0 > THRESHOLD && !holdoff_active_ch0) begin
      led_active_ch0 <= 1;
      holdoff_active_ch0 <= 1;
      counter_ch0 <= FLASH_CYCLES + HOLDOFF_CYCLES;
    end else if (counter_ch0 > 0) begin
      counter_ch0 <= counter_ch0 - 1;
      if (counter_ch0 < HOLDOFF_CYCLES) led_active_ch0 <= 0;
      if (counter_ch0 == 1) holdoff_active_ch0 <= 0;
    end else begin
      led_active_ch0 <= 0;
      holdoff_active_ch0 <= 0;
    end
  end
end

// Channel 1
reg led_active_ch1 = 0;
reg holdoff_active_ch1 = 0;
reg [31:0] counter_ch1 = 0;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    led_active_ch1 <= 0;
    holdoff_active_ch1 <= 0;
    counter_ch1 <= 0;
  end else begin
	  if (adc_ch1 > THRESHOLD && !holdoff_active_ch1) begin
      led_active_ch1 <= 1;
      holdoff_active_ch1 <= 1;
      counter_ch1 <= FLASH_CYCLES + HOLDOFF_CYCLES;
    end else if (counter_ch1 > 0) begin
      counter_ch1 <= counter_ch1 - 1;
      if (counter_ch1 < HOLDOFF_CYCLES) led_active_ch1 <= 0;
      if (counter_ch1 == 1) holdoff_active_ch1 <= 0;
    end else begin
      led_active_ch1 <= 0;
      holdoff_active_ch1 <= 0;
    end
  end
end

// Channel 2
reg led_active_ch2 = 0;
reg holdoff_active_ch2 = 0;
reg [31:0] counter_ch2 = 0;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    led_active_ch2 <= 0;
    holdoff_active_ch2 <= 0;
    counter_ch2 <= 0;
  end else begin
	  if (adc_ch2 > THRESHOLD && !holdoff_active_ch2) begin
      led_active_ch2 <= 1;
      holdoff_active_ch2 <= 1;
      counter_ch2 <= FLASH_CYCLES + HOLDOFF_CYCLES;
    end else if (counter_ch2 > 0) begin
      counter_ch2 <= counter_ch2 - 1;
      if (counter_ch2 < HOLDOFF_CYCLES) led_active_ch2 <= 0;
      if (counter_ch2 == 1) holdoff_active_ch2 <= 0;
    end else begin
      led_active_ch2 <= 0;
      holdoff_active_ch2 <= 0;
    end
  end
end

// Channel 3
reg led_active_ch3 = 0;
reg holdoff_active_ch3 = 0;
reg [31:0] counter_ch3 = 0;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    led_active_ch3 <= 0;
    holdoff_active_ch3 <= 0;
    counter_ch3 <= 0;
  end else begin
	  if (adc_ch3 > THRESHOLD && !holdoff_active_ch3) begin
      led_active_ch3 <= 1;
      holdoff_active_ch3 <= 1;
      counter_ch3 <= FLASH_CYCLES + HOLDOFF_CYCLES;
    end else if (counter_ch3 > 0) begin
      counter_ch3 <= counter_ch3 - 1;
      if (counter_ch3 < HOLDOFF_CYCLES) led_active_ch3 <= 0;
      if (counter_ch3 == 1) holdoff_active_ch3 <= 0;
    end else begin
      led_active_ch3 <= 0;
      holdoff_active_ch3 <= 0;
    end
  end
end

// Combine LEDs
//assign led_out = {led_active_ch3, led_active_ch2, led_active_ch1, led_active_ch0, 4'b0};
assign led_out = {4'b0, led_active_ch3, led_active_ch2, led_active_ch1, led_active_ch0};	

endmodule