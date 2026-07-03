@echo off
setlocal

REM Run from this testbench project root, even when this BAT is double-clicked from Scripts.
cd /d "%~dp0.."

echo ============================================================
echo 1000x500 RGB to HSV to RGB Match-Input BMP Testbench
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
if not exist "GHDL_Work" mkdir "GHDL_Work"

del /q "GHDL_Work/work-obj*.cf" 2>nul


echo Analyzing VHDL source files...
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/div16_8_8.vhd" || goto :error
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/rgb_hsv.vhd" || goto :error
ghdl -a --std=08 --workdir=GHDL_Work "../Source_Files/hsv2rgb.vhd" || goto :error
ghdl -a --std=08 --workdir=GHDL_Work "Testbench_Files/tb_rgb_hsv2rgb_match_input_bmp.vhd" || goto :error
ghdl -a --std=08 --workdir=GHDL_Work "Testbench_Files/testbench.vhd" || goto :error

echo.
echo Elaborating testbench...
ghdl -e --std=08 --workdir=GHDL_Work testbench || goto :error

echo.
echo Running simulation...
echo No fixed --stop-time is used. The testbench stops itself after the BMP frame is written.
ghdl -r --std=08 --workdir=GHDL_Work testbench || goto :error

if not exist "Generated_Outputs\output_rgb_hsv2rgb_match_input.bmp" (
    echo.
    echo ERROR: Simulation completed, but the output BMP was not found.
    echo Expected: Generated_Outputs\output_rgb_hsv2rgb_match_input.bmp
    echo Directory contents:
    dir "Generated_Outputs"
    goto :error
)

echo.
echo DONE. Generated RGB HSV round-trip BMP output:
dir "Generated_Outputs\output_rgb_hsv2rgb_match_input.bmp"
echo.
echo Default pipeline: RGB input -^> rgb_hsv -^> hsv2rgb -^> RGB output.
echo Match-input mode uses PREFILTER_MODE=0 and ENABLE_FLAT_COLOR=false.
echo.
pause
exit /b 0

:error
echo.
echo ERROR: GHDL compile, elaboration, or simulation failed.
echo Check the message above for the first failing VHDL file or simulation assertion.
pause
exit /b 1
