$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host "============================================================"
Write-Host "1000x500 RGB to HSV to RGB Match-Input BMP Testbench"
Write-Host "Project: $(Get-Location)"
Write-Host "============================================================"

if (-not (Get-Command ghdl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: ghdl was not found in PATH."
    exit 1
}

if (-not (Test-Path "Input_Image/1000_500.bmp")) {
    Write-Host "ERROR: Input_Image/1000_500.bmp not found."
    exit 1
}

New-Item -ItemType Directory -Force -Path "Generated_Outputs" | Out-Null
New-Item -ItemType Directory -Force -Path "GHDL_Work" | Out-Null
Remove-Item "GHDL_Work/work-obj*.cf" -ErrorAction SilentlyContinue
Remove-Item "Generated_Outputs/output_rgb_hsv2rgb_match_input.bmp" -ErrorAction SilentlyContinue

Write-Host "Analyzing VHDL source files..."
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/div16_8_8.vhd"
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/rgb_hsv.vhd"
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/hsv2rgb.vhd"
ghdl -a --std=08 --workdir=GHDL_Work "Testbench_Files/tb_rgb_hsv2rgb_match_input_bmp.vhd"
ghdl -a --std=08 --workdir=GHDL_Work "Testbench_Files/testbench.vhd"

Write-Host "Elaborating testbench..."
ghdl -e --std=08 --workdir=GHDL_Work testbench

Write-Host "Running simulation..."
ghdl -r --std=08 --workdir=GHDL_Work testbench

Write-Host "DONE. Generated_Outputs/output_rgb_hsv2rgb_match_input.bmp"
