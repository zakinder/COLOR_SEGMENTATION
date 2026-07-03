# Run RGB HSV2RGB Match-Input Testbench on Windows

1. Install GHDL and make sure `ghdl.exe` is in PATH.
2. Keep the input BMP here:

```text
Input_Image/1000_500.bmp
```

3. Double-click:

```text
Run_Testbench.bat
```

or run from PowerShell:

```powershell
.\Scripts\Run_Testbench_1000x500_RGB_HSV2RGB_MATCH_INPUT.ps1
```

Generated output:

```text
Generated_Outputs/output_rgb_hsv2rgb_match_input.bmp
```

Default match-input settings:

```vhdl
-- Source_Files/rgb_hsv.vhd
constant ENABLE_FLAT_COLOR       : boolean := false;
constant LOW_SATURATION_TO_GRAY  : boolean := false;
constant LOW_VALUE_TO_BLACK      : boolean := false;

-- Testbench_Files/tb_rgb_hsv2rgb_match_input_bmp.vhd
constant PREFILTER_MODE : integer := 0;
```
