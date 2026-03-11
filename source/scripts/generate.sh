#!/bin/bash

# generate_bit_bin.sh - Generate .bit.bin for fpgautil from .bit
# Usage: ./generate.sh path/to/project_name.bit

if [ $# -ne 1 ]; then
  echo "ERROR: No .bit file provided!"
  echo "Usage: $0 path/to/project_name.bit"
  exit 1
fi

BIT_FILE="$1"

if [ ! -f "$BIT_FILE" ]; then
  echo "ERROR: .bit file not found: $BIT_FILE"
  exit 1
fi

# Extract filename without extension for output
BASE_NAME=$(basename "$BIT_FILE" .bit)
BIN_FILE="${BASE_NAME}.bit.bin"
BIF_FILE="${BASE_NAME}.bif"

# Create .bif file
echo "all:" > "$BIF_FILE"
echo "{" >> "$BIF_FILE"
echo "  $BIT_FILE" >> "$BIF_FILE"
echo "}" >> "$BIF_FILE"

# Run bootgen
# If bootgen is not in PATH, uncomment and set full path
# BOOTGEN="/home/nay/Programs/Xilinx/Vivado/2025.1/bin/bootgen"
BOOTGEN="bootgen"

echo "Running bootgen to generate $BIN_FILE ..."
$BOOTGEN -arch zynq -process_bitstream bin -w on -o "$BIN_FILE" -image "$BIF_FILE"

if [ -f "$BIN_FILE" ]; then
  echo "Success! Generated: $BIN_FILE"
  echo "Load with: fpgautil -b $BIN_FILE"
else
  echo "ERROR: Failed to generate .bit.bin"
  exit 1
fi