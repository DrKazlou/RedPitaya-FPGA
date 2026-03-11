# 1. PS7 Configuration
cell xilinx.com:ip:processing_system7 ps_0 {
  PCW_IMPORT_BOARD_PRESET source/red_pitaya.xml
  PCW_FPGA0_PERIPHERAL_FREQMHZ 125.0
  PCW_USE_M_AXI_GP0 1
  PCW_USE_S_AXI_HP0 1
} {
  M_AXI_GP0_ACLK ps_0/FCLK_CLK0
  S_AXI_HP0_ACLK ps_0/FCLK_CLK0
}

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {
  make_external {FIXED_IO, DDR}
  Master Disable
  Slave Disable
} [get_bd_cells ps_0]

set axis_freq 125000000

# 2. Clocks and Resets
cell xilinx.com:ip:xlconstant const_0 {
  CONST_WIDTH 1 
  CONST_VAL 1
}

cell xilinx.com:ip:proc_sys_reset rst_0 {} {
  ext_reset_in const_0/dout
  slowest_sync_clk ps_0/FCLK_CLK0
}

cell xilinx.com:ip:clk_wiz clk_wiz_200mhz {
  PRIM_IN_FREQ 125.0
  CLKOUT1_USED true
  CLKOUT1_REQUESTED_OUT_FREQ 200.0
} {
  clk_in1 ps_0/FCLK_CLK0
}

# 3. AXI Interconnects
# GP0: Control path (PS → Hub + 4 DMAs)
cell xilinx.com:ip:axi_interconnect gp0_interconnect {
  NUM_MI 5
  NUM_SI 1
} {
  ACLK ps_0/FCLK_CLK0
  ARESETN rst_0/peripheral_aresetn
  S00_ACLK ps_0/FCLK_CLK0
  S00_ARESETN rst_0/peripheral_aresetn
  M00_ACLK ps_0/FCLK_CLK0
  M00_ARESETN rst_0/peripheral_aresetn
  M01_ACLK ps_0/FCLK_CLK0
  M01_ARESETN rst_0/peripheral_aresetn
  M02_ACLK ps_0/FCLK_CLK0
  M02_ARESETN rst_0/peripheral_aresetn
  M03_ACLK ps_0/FCLK_CLK0
  M03_ARESETN rst_0/peripheral_aresetn
  M04_ACLK ps_0/FCLK_CLK0
  M04_ARESETN rst_0/peripheral_aresetn
  S00_AXI ps_0/M_AXI_GP0
}

# HP0: Data path (4 DMAs → PS DDR)
cell xilinx.com:ip:axi_interconnect hp0_interconnect {
  NUM_MI 1
  NUM_SI 4
} {
  ACLK ps_0/FCLK_CLK0
  ARESETN rst_0/peripheral_aresetn
  S00_ACLK ps_0/FCLK_CLK0
  S00_ARESETN rst_0/peripheral_aresetn
  S01_ACLK ps_0/FCLK_CLK0
  S01_ARESETN rst_0/peripheral_aresetn
  S02_ACLK ps_0/FCLK_CLK0
  S02_ARESETN rst_0/peripheral_aresetn
  S03_ACLK ps_0/FCLK_CLK0
  S03_ARESETN rst_0/peripheral_aresetn
  M00_ACLK ps_0/FCLK_CLK0
  M00_ARESETN rst_0/peripheral_aresetn
  M00_AXI ps_0/S_AXI_HP0
}

# 4. AXI Hub (Configuration and Status)
cell user.org:user:axi_hub:1.0 hub_0 {
  CFG_DATA_WIDTH 128
  STS_DATA_WIDTH 128
} {
  aclk ps_0/FCLK_CLK0
  aresetn rst_0/peripheral_aresetn
  s_axi gp0_interconnect/M00_AXI
}

# 5. ADC Deserializer
cell user.org:user:adc_deserializer:1.0 adc_0 {} {
  sys_clk ps_0/FCLK_CLK0
  rst_n rst_0/peripheral_aresetn
  ref_clk_200mhz clk_wiz_200mhz/clk_out1
}

# Set clock frequencies
set_property -dict [list CONFIG.FREQ_HZ $axis_freq CONFIG.FREQ_HZ.VALUE_SRC USER] [get_bd_pins adc_0/adc_clk_out]
set_property -dict [list CONFIG.FREQ_HZ $axis_freq CONFIG.FREQ_HZ.VALUE_SRC USER] [get_bd_pins ps_0/FCLK_CLK0]

# 6. ARM Signal (shared by both channels)
cell user.org:user:port_slicer:1.0 arm_slice {
  DIN_WIDTH 128
  DIN_FROM 0
  DIN_TO 0
} {
  din hub_0/cfg_data
}

# ===========================================================================
# CHANNEL 0 - INDEPENDENT ACQUISITION PATH
# ===========================================================================

# Threshold Slicer
cell user.org:user:port_slicer:1.0 th_slice_0 {
  DIN_WIDTH 128
  DIN_FROM 14
  DIN_TO 1
} {
  din hub_0/cfg_data
}

# Comparator
cell user.org:user:comparator:1.0 comp_0 {} {
  clk adc_0/adc_clk_out
  adc_data adc_0/adc_ch0
  threshold th_slice_0/dout
}

# Triggered Buffer
cell user.org:user:axis_triggered_buffer:1.0 buffer_0 {
  CHANNEL_ID 0
} {
  clk adc_0/adc_clk_out
  rst_n rst_0/peripheral_aresetn
  adc_data adc_0/adc_ch0
  trigger_in comp_0/hit
  arm arm_slice/dout
}

# CDC FIFO (ADC clock → PS clock domain)
cell xilinx.com:ip:axis_data_fifo axis_fifo_0 {
  TDATA_NUM_BYTES 8
  FIFO_DEPTH 4096
  IS_ACLK_ASYNC 1
  HAS_TLAST 1
} {
  s_axis_aclk adc_0/adc_clk_out
  s_axis_aresetn rst_0/peripheral_aresetn
  m_axis_aclk ps_0/FCLK_CLK0
  S_AXIS buffer_0/m_axis
}

# DMA Engine
cell xilinx.com:ip:axi_dma axi_dma_0 {
  C_INCLUDE_SG 0
  C_INCLUDE_MM2S 0
  C_M_AXI_S2MM_DATA_WIDTH 64
  C_S_AXIS_S2MM_TDATA_WIDTH 64
} {
  m_axi_s2mm_aclk ps_0/FCLK_CLK0
  s_axi_lite_aclk ps_0/FCLK_CLK0
  axi_resetn rst_0/peripheral_aresetn
  S_AXIS_S2MM axis_fifo_0/M_AXIS
  S_AXI_LITE gp0_interconnect/M01_AXI
  M_AXI_S2MM hp0_interconnect/S00_AXI
}

# ===========================================================================
# CHANNEL 1 - INDEPENDENT ACQUISITION PATH
# ===========================================================================

# Threshold Slicer
cell user.org:user:port_slicer:1.0 th_slice_1 {
  DIN_WIDTH 128
  DIN_FROM 28
  DIN_TO 15
} {
  din hub_0/cfg_data
}

# Comparator
cell user.org:user:comparator:1.0 comp_1 {} {
  clk adc_0/adc_clk_out
  adc_data adc_0/adc_ch1
  threshold th_slice_1/dout
}

# Triggered Buffer
cell user.org:user:axis_triggered_buffer:1.0 buffer_1 {
  CHANNEL_ID 1
} {
  clk adc_0/adc_clk_out
  rst_n rst_0/peripheral_aresetn
  adc_data adc_0/adc_ch1
  trigger_in comp_1/hit
  arm arm_slice/dout
}

# CDC FIFO (ADC clock → PS clock domain)
cell xilinx.com:ip:axis_data_fifo axis_fifo_1 {
  TDATA_NUM_BYTES 8
  FIFO_DEPTH 4096
  IS_ACLK_ASYNC 1
  HAS_TLAST 1
} {
  s_axis_aclk adc_0/adc_clk_out
  s_axis_aresetn rst_0/peripheral_aresetn
  m_axis_aclk ps_0/FCLK_CLK0
  S_AXIS buffer_1/m_axis
}

# DMA Engine
cell xilinx.com:ip:axi_dma axi_dma_1 {
  C_INCLUDE_SG 0
  C_INCLUDE_MM2S 0
  C_M_AXI_S2MM_DATA_WIDTH 64
  C_S_AXIS_S2MM_TDATA_WIDTH 64
} {
  m_axi_s2mm_aclk ps_0/FCLK_CLK0
  s_axi_lite_aclk ps_0/FCLK_CLK0
  axi_resetn rst_0/peripheral_aresetn
  S_AXIS_S2MM axis_fifo_1/M_AXIS
  S_AXI_LITE gp0_interconnect/M02_AXI
  M_AXI_S2MM hp0_interconnect/S01_AXI
}

# ===========================================================================
# CHANNEL 2 - INDEPENDENT ACQUISITION PATH
# ===========================================================================

cell user.org:user:port_slicer:1.0 th_slice_2 {
  DIN_WIDTH 128
  DIN_FROM 42
  DIN_TO 29
} {
  din hub_0/cfg_data
}

cell user.org:user:comparator:1.0 comp_2 {} {
  clk adc_0/adc_clk_out
  adc_data adc_0/adc_ch2
  threshold th_slice_2/dout
}

cell user.org:user:axis_triggered_buffer:1.0 buffer_2 {
  CHANNEL_ID 2
} {
  clk adc_0/adc_clk_out
  rst_n rst_0/peripheral_aresetn
  adc_data adc_0/adc_ch2
  trigger_in comp_2/hit
  arm arm_slice/dout
}

cell xilinx.com:ip:axis_data_fifo axis_fifo_2 {
  TDATA_NUM_BYTES 8
  FIFO_DEPTH 4096
  IS_ACLK_ASYNC 1
  HAS_TLAST 1
} {
  s_axis_aclk adc_0/adc_clk_out
  s_axis_aresetn rst_0/peripheral_aresetn
  m_axis_aclk ps_0/FCLK_CLK0
  S_AXIS buffer_2/m_axis
}

cell xilinx.com:ip:axi_dma axi_dma_2 {
  C_INCLUDE_SG 0
  C_INCLUDE_MM2S 0
  C_M_AXI_S2MM_DATA_WIDTH 64
  C_S_AXIS_S2MM_TDATA_WIDTH 64
} {
  m_axi_s2mm_aclk ps_0/FCLK_CLK0
  s_axi_lite_aclk ps_0/FCLK_CLK0
  axi_resetn rst_0/peripheral_aresetn
  S_AXIS_S2MM axis_fifo_2/M_AXIS
  S_AXI_LITE gp0_interconnect/M03_AXI
  M_AXI_S2MM hp0_interconnect/S02_AXI
}

# ===========================================================================
# CHANNEL 3 - INDEPENDENT ACQUISITION PATH
# ===========================================================================

cell user.org:user:port_slicer:1.0 th_slice_3 {
  DIN_WIDTH 128
  DIN_FROM 56
  DIN_TO 43
} {
  din hub_0/cfg_data
}

cell user.org:user:comparator:1.0 comp_3 {} {
  clk adc_0/adc_clk_out
  adc_data adc_0/adc_ch3
  threshold th_slice_3/dout
}

cell user.org:user:axis_triggered_buffer:1.0 buffer_3 {
  CHANNEL_ID 3
} {
  clk adc_0/adc_clk_out
  rst_n rst_0/peripheral_aresetn
  adc_data adc_0/adc_ch3
  trigger_in comp_3/hit
  arm arm_slice/dout
}

cell xilinx.com:ip:axis_data_fifo axis_fifo_3 {
  TDATA_NUM_BYTES 8
  FIFO_DEPTH 4096
  IS_ACLK_ASYNC 1
  HAS_TLAST 1
} {
  s_axis_aclk adc_0/adc_clk_out
  s_axis_aresetn rst_0/peripheral_aresetn
  m_axis_aclk ps_0/FCLK_CLK0
  S_AXIS buffer_3/m_axis
}

cell xilinx.com:ip:axi_dma axi_dma_3 {
  C_INCLUDE_SG 0
  C_INCLUDE_MM2S 0
  C_M_AXI_S2MM_DATA_WIDTH 64
  C_S_AXIS_S2MM_TDATA_WIDTH 64
} {
  m_axi_s2mm_aclk ps_0/FCLK_CLK0
  s_axi_lite_aclk ps_0/FCLK_CLK0
  axi_resetn rst_0/peripheral_aresetn
  S_AXIS_S2MM axis_fifo_3/M_AXIS
  S_AXI_LITE gp0_interconnect/M04_AXI
  M_AXI_S2MM hp0_interconnect/S03_AXI
}

# ===========================================================================
# MONITORING AND STATUS
# ===========================================================================

# Frequency Counters (FPGA-level rate measurement)
cell user.org:user:freq_counter:1.0 freq_0 {} {
  clk adc_0/adc_clk_out
  rst_n rst_0/peripheral_aresetn
  adc_ch0 adc_0/adc_ch0
  adc_ch1 adc_0/adc_ch1
  adc_ch2 adc_0/adc_ch2
  adc_ch3 adc_0/adc_ch3
  threshold0 th_slice_0/dout
  threshold1 th_slice_1/dout
  threshold2 th_slice_2/dout
  threshold3 th_slice_3/dout
}

# LED Indicators
cell user.org:user:threshold_led:1.0 threshold_led_0 {} {
  clk adc_0/adc_clk_out
  rst_n rst_0/peripheral_aresetn
  adc_ch0 adc_0/adc_ch0
  adc_ch1 adc_0/adc_ch1
  adc_ch2 adc_0/adc_ch2
  adc_ch3 adc_0/adc_ch3
}

# Busy flags concatenation
cell xilinx.com:ip:xlconcat busy_concat {
  NUM_PORTS 4
  IN0_WIDTH 1
  IN1_WIDTH 1
  IN2_WIDTH 1
  IN3_WIDTH 1
} {
  In0 buffer_0/busy_out
  In1 buffer_1/busy_out
  In2 buffer_2/busy_out
  In3 buffer_3/busy_out
}

# Padding
cell xilinx.com:ip:xlconstant pad_12bit {
  CONST_WIDTH 12
  CONST_VAL 0
}

# Status: [3:0]=busy, [31:4]=freq0, [59:32]=freq1, [87:60]=freq2, [115:88]=freq3, [127:116]=pad
cell xilinx.com:ip:xlconcat sts_concat {
  NUM_PORTS 6
  IN0_WIDTH 4
  IN1_WIDTH 28
  IN2_WIDTH 28
  IN3_WIDTH 28
  IN4_WIDTH 28
  IN5_WIDTH 12
} {
  In0 busy_concat/dout
  In1 freq_0/freq_ch0
  In2 freq_0/freq_ch1
  In3 freq_0/freq_ch2
  In4 freq_0/freq_ch3
  In5 pad_12bit/dout
  dout hub_0/sts_data
}

# 8. External Ports
make_bd_pins_external [get_bd_pins adc_0/adc_dat_i_flat] -name adc_dat_i_flat
make_bd_pins_external [get_bd_pins adc_0/adc_clk_i_flat] -name adc_clk_i_flat
create_bd_port -dir O -from 7 -to 0 led_o
connect_bd_net [get_bd_pins threshold_led_0/led_out] [get_bd_ports led_o]

# Set on external input clock bus (now possible after Verilog update)
set_property -dict [list CONFIG.FREQ_HZ $axis_freq CONFIG.FREQ_HZ.VALUE_SRC USER] [get_bd_ports adc_clk_i_flat]

# Hub
assign_bd_address [get_bd_addr_segs {hub_0/s_axi/reg0}]
set_property offset 0x40000000 [get_bd_addr_segs {ps_0/Data/SEG_hub_0_reg0}]
set_property range 64K [get_bd_addr_segs {ps_0/Data/SEG_hub_0_reg0}]

# DMA 0
assign_bd_address [get_bd_addr_segs {axi_dma_0/S_AXI_LITE/Reg}]
set_property offset 0x40020000 [get_bd_addr_segs {ps_0/Data/SEG_axi_dma_0_Reg}]
set_property range 64K [get_bd_addr_segs {ps_0/Data/SEG_axi_dma_0_Reg}]

# DMA 1
assign_bd_address [get_bd_addr_segs {axi_dma_1/S_AXI_LITE/Reg}]
set_property offset 0x40030000 [get_bd_addr_segs {ps_0/Data/SEG_axi_dma_1_Reg}]
set_property range 64K [get_bd_addr_segs {ps_0/Data/SEG_axi_dma_1_Reg}]

# DMA 2
assign_bd_address [get_bd_addr_segs {axi_dma_2/S_AXI_LITE/Reg}]
set_property offset 0x40040000 [get_bd_addr_segs {ps_0/Data/SEG_axi_dma_2_Reg}]
set_property range 64K [get_bd_addr_segs {ps_0/Data/SEG_axi_dma_2_Reg}]

# DMA 3
assign_bd_address [get_bd_addr_segs {axi_dma_3/S_AXI_LITE/Reg}]
set_property offset 0x40050000 [get_bd_addr_segs {ps_0/Data/SEG_axi_dma_3_Reg}]
set_property range 64K [get_bd_addr_segs {ps_0/Data/SEG_axi_dma_3_Reg}]


assign_bd_address [get_bd_addr_segs {ps_0/S_AXI_HP0/HP0_DDR_LOWOCM}]

create_bd_addr_seg -range 64K -offset 0x41000000 [get_bd_addr_spaces ps_0/Data] [get_bd_addr_segs hub_0/s_axi/reg0] SEG_hub_0_sts


validate_bd_design
save_bd_design