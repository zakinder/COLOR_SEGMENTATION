# Source Files

These VHDL files are portable. The testbench now uses `flat_color_segment_pkg.vhd` for the default flat-color segmentation path.

| File | Purpose |
|---|---|
| `flat_color_segment_pkg.vhd` | Reusable BMP/GHDL flat-color segmentation helper package: 3x3 median, HSV flat classifier, majority cleanup. |
| `rgb_hsv.vhd` | Converts 8-bit RGB to 8-bit HSV. |
| `hsv2rgb.vhd` | Converts 8-bit HSV to 8-bit RGB. |
| `div16_8_8.vhd` | Portable 16-bit by 8-bit divider helper retained with the source set. |

Only standard IEEE libraries are required:

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
```


## `rgb_hsv.vhd` adjustment constants

`rgb_hsv.vhd` includes saturation/value gain and offset constants. Defaults preserve original behavior.

```vhdl
constant SATURATION_GAIN_PERCENT : integer := 100;
constant SATURATION_OFFSET       : integer := 0;

constant VALUE_GAIN_PERCENT      : integer := 100;
constant VALUE_OFFSET            : integer := 0;
```

`GAIN_PERCENT` applies a percentage scale and `OFFSET` adds/subtracts an 8-bit count after scaling. Outputs are clamped to `0..255`.
