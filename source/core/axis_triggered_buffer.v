`timescale 1ns / 1ps

module axis_triggered_buffer # (
    parameter integer CHANNEL_ID   = 0,     
    parameter integer BUFFER_DEPTH = 1024,
    parameter integer PRE_TRIGGER  = 256
) (
    input  clk,
    input  rst_n,
    input  signed [13:0] adc_data,
    
    // Trigger input (In this step, connected directly to comparator)
    input  trigger_in, 
    input  arm,
    
    // AXI-Stream Master Interface
    output reg [63:0] m_axis_tdata,
    output reg        m_axis_tvalid,
    output reg        m_axis_tlast,
    input             m_axis_tready,
    
    output reg        done_out,
	output reg 		  busy_out //Safe disarm flag
);


	
    // States
    localparam IDLE      = 3'd0;
    localparam PRE_FILL  = 3'd1;
    localparam ARMED     = 3'd2;
    localparam POST_FILL = 3'd3;
    localparam SEND_HDR  = 3'd4;
    localparam SEND_DATA = 3'd5;

    reg [2:0] state;
    reg [9:0] wr_ptr, rd_ptr;
    reg [31:0] cnt;
    
    // Simple 48-bit timestamp for header
    reg [47:0] timestamp_counter;
    reg [47:0] latched_ts;
    
    always @(posedge clk) begin
        if (!rst_n) timestamp_counter <= 0;
        else timestamp_counter <= timestamp_counter + 1;
    end

    reg [15:0] bram [0:BUFFER_DEPTH-1];

	// BUSY FLAG LOGIC
    always @(posedge clk) begin
        if (!rst_n) begin
            busy_out <= 0;
        end else begin
            case (state)
                // Not busy during these states
                IDLE, PRE_FILL, ARMED, POST_FILL: busy_out <= 0;
                
                // BUSY during transmission - do NOT disarm!
                SEND_HDR, SEND_DATA: busy_out <= 1;
                
                default: busy_out <= 0;
            endcase
        end
    end
	
       // Main state machine
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            m_axis_tvalid <= 0;
            m_axis_tlast <= 0;
            done_out <= 0;
            wr_ptr <= 0;
            rd_ptr <= 0;
            cnt <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done_out <= 0;
                    m_axis_tvalid <= 0;
                    m_axis_tlast <= 0;
                    wr_ptr <= 0;
                    cnt <= 0;
                    
                    if (arm) begin
                        state <= PRE_FILL;
                    end
                end

                PRE_FILL: begin
                    // Fill pre-trigger buffer
                    bram[wr_ptr] <= {2'b0, adc_data};
                    wr_ptr <= wr_ptr + 1;
                    
                    if (wr_ptr == PRE_TRIGGER) begin
                        state <= ARMED;
                    end
                    
                    // SAFE DISARM: Only if not in transmission
                    if (!arm && !busy_out) begin
                        state <= IDLE;
                    end
                end

                ARMED: begin
                    // Continuously capture, circular buffer style
                    bram[wr_ptr] <= {2'b0, adc_data};
                    wr_ptr <= wr_ptr + 1;
                    
                    // Wait for trigger
                    if (trigger_in) begin
                        latched_ts <= timestamp_counter;
                        cnt <= 0;
                        state <= POST_FILL;
                    end
                    
                    // SAFE DISARM: Only if not in transmission
                    if (!arm && !busy_out) begin
                        state <= IDLE;
                    end
                end

                POST_FILL: begin
                    // Fill remaining post-trigger samples
                    bram[wr_ptr] <= {2'b0, adc_data};
                    wr_ptr <= wr_ptr + 1;
                    cnt <= cnt + 1;
                    
                    if (cnt == (BUFFER_DEPTH - PRE_TRIGGER - 1)) begin
                        // Calculate readout start pointer
                        rd_ptr <= (wr_ptr - BUFFER_DEPTH + 1);
                        state <= SEND_HDR;
                    end
                    
                    // NOTE: Do NOT check arm here - committed to sending data!
                end

                SEND_HDR: begin
                    // Send header word
                    if (m_axis_tready || !m_axis_tvalid) begin
                        // Header format: [63:50]=0, [49:48]=CH_ID, [47:0]=Timestamp
                        m_axis_tdata <= {14'b0, CHANNEL_ID[1:0], latched_ts};
                        m_axis_tvalid <= 1;
                        m_axis_tlast <= 0;
                        cnt <= 0;
                        state <= SEND_DATA;
                    end
                    
                    // NOTE: Do NOT check arm - busy flag prevents disarm
                end

                SEND_DATA: begin
                    // Stream out all samples
                    if (m_axis_tready) begin
                        // Pack sample into 64-bit word (lower 16 bits)
                        m_axis_tdata <= {48'b0, bram[rd_ptr]}; 
                        rd_ptr <= rd_ptr + 1;
                        cnt <= cnt + 1;
                        
                        // Assert TLAST on final sample
                        m_axis_tlast <= (cnt == BUFFER_DEPTH - 1);
                        
                        if (m_axis_tlast) begin
                            m_axis_tvalid <= 0;
                            done_out <= 1;
                            state <= IDLE;
                        end
                    end
                    
                    // NOTE: Do NOT check arm - busy flag prevents disarm
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
            
endmodule