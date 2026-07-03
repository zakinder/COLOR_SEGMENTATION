$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host "============================================================"
Write-Host "1000x500 Flat-Color Segment BMP Testbench"
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
# Keep existing BMP files in Generated_Outputs. Do not delete prior simulation outputs.
$DefaultOutputBmp = "Generated_Outputs/FlatSeg_Slt_40_Vdark_20_Vwhite_210_Maj_5_Pass_2.bmp"

# Optional GHDL generic overrides. Leave empty to use packaged flat-color defaults.
# Default path:
#   RGB BMP -> flat_color_segment_pkg 3x3 median -> HSV/object-aware segmentation -> majority cleanup -> RGB BMP
#
# Legacy rgb_hsv -> hsv2rgb round-trip example:
# $GhdlRunGenerics = @(
#   "-gUSE_FLAT_SEGMENT_PACKAGE=false",
#   "-gRGB_HSV_ENABLE_FLAT_COLOR=false"
# )
#
# Stronger package cleanup example:
# $GhdlRunGenerics = @(
#   "-gFLAT_SEGMENT_MAJORITY_MIN_COUNT=5",
#   "-gFLAT_SEGMENT_MAJORITY_PASSES=3"
# )
#
# Output filename defaults to AUTO and encodes active package controls, for example:
#   $DefaultOutputBmp
# Override with: "-gOUTPUT_BMP_FILE=Generated_Outputs/my_fixed_name.bmp"
$GhdlRunGenerics = @()

Write-Host "Analyzing VHDL source files..."
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/flat_color_segment_pkg.vhd"
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/div16_8_8.vhd"
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/rgb_hsv.vhd"
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/hsv2rgb.vhd"
ghdl -a --std=08 --workdir=GHDL_Work "Testbench_Files/tb_rgb_hsv2rgb_match_input_bmp.vhd"

Write-Host "Elaborating testbench..."
ghdl -e --std=08 --workdir=GHDL_Work tb_rgb_hsv2rgb_match_input_bmp

Write-Host "Running simulation..."
Write-Host "Generic overrides: $($GhdlRunGenerics -join ' ')"
ghdl -r --std=08 --workdir=GHDL_Work tb_rgb_hsv2rgb_match_input_bmp @GhdlRunGenerics

$OutputBmps = Get-ChildItem "Generated_Outputs" -Filter "*.bmp" -ErrorAction SilentlyContinue
if (-not $OutputBmps) {
    Write-Host "ERROR: Simulation completed, but no output BMP was found."
    Write-Host "Expected default AUTO name: $DefaultOutputBmp"
    exit 1
}

Write-Host "DONE. Generated flat-color segmented BMP output:"
$OutputBmps | Format-Table Name, Length, LastWriteTime
