@echo off
setlocal

REM Run all 28 configurations listed in:
REM   Docs\AUTO_28_OUTPUT_CONFIG_MATRIX.csv
REM This BAT launches the PowerShell automation script because it handles
REM output filenames with spaces, including " - Copy.bmp".

cd /d "%~dp0"

echo ============================================================
echo 1000x500 Automated 28-Output Testbench
echo ============================================================
echo.

where powershell >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\Scripts\Run_All_28_Output_Images.ps1"
if errorlevel 1 goto :error

echo.
echo DONE. Check Generated_Outputs for the 28 BMP files.
echo.
pause
exit /b 0

:error
echo.
echo ERROR: Automated 28-output run failed.
echo Check Generated_Outputs\Run_All_28_Outputs_Log.txt and the GHDL messages above.
pause
exit /b 1
