# COLOR_SEGMENTATION
COLOR_SEGMENTATION

This package is configured for a color-preserving round trip:

```text
RGB input -> rgb_hsv -> hsv2rgb -> RGB output
```

Important default settings:

```vhdl
-- Source_Files/rgb_hsv.vhd
constant ENABLE_FLAT_COLOR       : boolean := false;
constant LOW_SATURATION_TO_GRAY  : boolean := false;
constant LOW_VALUE_TO_BLACK      : boolean := false;

-- Testbench_Files/tb_rgb_hsv2rgb_match_input_bmp.vhd
constant PREFILTER_MODE : integer := 0;
```

Output:

```text
Testbench_1000x500_RGB_HSV2RGB_MATCH_INPUT/Generated_Outputs/output_rgb_hsv2rgb_match_input.bmp
```

The result should visually match `Input_Image/1000_500.bmp`. A few numeric pixel differences can still occur because RGB->HSV->RGB uses 8-bit fixed-point integer arithmetic.
