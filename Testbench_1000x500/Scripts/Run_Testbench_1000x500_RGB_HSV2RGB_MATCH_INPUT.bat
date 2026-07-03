@echo off
setlocal

REM Run from this testbench project root, even when this BAT is double-clicked from Scripts.
cd /d "%~dp0.."

echo ============================================================
echo 1000x500 Flat-Color Segment BMP Testbench
echo Project: %CD%
echo ============================================================
echo.

where ghdl >nul 2>nul
if errorlevel 1 (
    echo ERROR: ghdl was not found in PATH.
    echo Install GHDL or add the GHDL bin folder to PATH.
    pause
    exit /b 1
)

if not exist "Input_Image/1000_500.bmp" (
    echo ERROR: Input_Image/1000_500.bmp not found.
    echo Put your 1000x500 24-bit uncompressed BMP in Input_Image.
    pause
    exit /b 1
)

if not exist "Generated_Outputs" mkdir "Generated_Outputs"
REM Keep existing BMP files in Generated_Outputs. Do not delete prior simulation outputs.
if not exist "GHDL_Work" mkdir "GHDL_Work"

del /q "GHDL_Work/work-obj*.cf" 2>nul


set "DEFAULT_OUTPUT_BMP=Generated_Outputs\FlatSeg_Slt_40_Vdark_20_Vwhite_210_Maj_5_Pass_2.bmp"

REM Optional GHDL generic overrides. Leave empty to use packaged flat-color defaults.
REM Default path:
REM   RGB BMP -> flat_color_segment_pkg 3x3 median -> HSV/object-aware segmentation -> majority cleanup -> RGB BMP
REM
REM Example: disable the package path and use the legacy rgb_hsv -> hsv2rgb round-trip path:
REM set "GHDL_RUN_GENERICS=-gUSE_FLAT_SEGMENT_PACKAGE=false -gRGB_HSV_ENABLE_FLAT_COLOR=false"
REM
REM Example: stronger cleanup from the package path:
REM set "GHDL_RUN_GENERICS=-gFLAT_SEGMENT_MAJORITY_MIN_COUNT=5 -gFLAT_SEGMENT_MAJORITY_PASSES=3"
REM
REM Output filename defaults to AUTO and encodes active package controls, for example:
REM Generated_Outputs\FlatSeg_Slt_40_Vdark_20_Vwhite_210_Maj_5_Pass_2.bmp
REM Override with -gOUTPUT_BMP_FILE=Generated_Outputs\my_fixed_name.bmp when needed.
set "GHDL_RUN_GENERICS="

echo Analyzing VHDL source files...
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/flat_color_segment_pkg.vhd" || goto :error
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/div16_8_8.vhd" || goto :error
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/rgb_hsv.vhd" || goto :error
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/hsv2rgb.vhd" || goto :error
ghdl -a --std=08 --workdir=GHDL_Work "Testbench_Files/tb_rgb_hsv2rgb_match_input_bmp.vhd" || goto :error

echo.
echo Elaborating testbench...
ghdl -e --std=08 --workdir=GHDL_Work tb_rgb_hsv2rgb_match_input_bmp || goto :error

echo.
echo Running simulation...
echo No fixed --stop-time is used. The testbench stops itself after the BMP frame is written.
echo Generic overrides: %GHDL_RUN_GENERICS%
ghdl -r --std=08 --workdir=GHDL_Work tb_rgb_hsv2rgb_match_input_bmp %GHDL_RUN_GENERICS% || goto :error

if not exist "Generated_Outputs\*.bmp" (
    echo.
    echo ERROR: Simulation completed, but no output BMP was found.
    echo Expected default AUTO name: %DEFAULT_OUTPUT_BMP%
    echo Directory contents:
    dir "Generated_Outputs"
    goto :error
)

echo.
echo DONE. Generated flat-color segmented BMP output:
dir "Generated_Outputs\*.bmp"
echo.
echo Default pipeline: RGB input -^> flat_color_segment_pkg median -^> HSV segment -^> majority cleanup -^> RGB output.
echo Set USE_FLAT_SEGMENT_PACKAGE=false to run the legacy rgb_hsv -^> hsv2rgb path.
echo.
pause
exit /b 0

:error
echo.
echo ERROR: GHDL compile, elaboration, or simulation failed.
echo Check the message above for the first failing VHDL file or simulation assertion.
pause
exit /b 1
