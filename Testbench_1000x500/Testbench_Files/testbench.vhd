-------------------------------------------------------------------------------
-- File        : testbench.vhd
-- Description : Top-level wrapper for the pre-filtered RGB->HSV->RGB BMP test.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity testbench is
end entity testbench;

architecture sim of testbench is
begin

  u_test : entity work.tb_rgb_hsv2rgb_match_input_bmp
    generic map (
      INPUT_BMP_FILE  => "Input_Image/1000_500.bmp",
      OUTPUT_BMP_FILE => "Generated_Outputs/output_rgb_hsv2rgb_match_input.bmp"
    );

end architecture sim;
