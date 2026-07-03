-------------------------------------------------------------------------------
-- File        : hsv2rgb.vhd
-- Description : Portable HSV-to-RGB converter using only IEEE std_logic_1164
--               and numeric_std. No project-specific channel records are used.
--
-- Color format:
--   Input : HSV, 8 bits/channel
--           i_hue        = 0..255 mapped around the 0..360 degree hue circle
--           i_saturation = 0..255
--           i_value      = 0..255
--   Output: RGB, 8 bits/channel
--
-- Latency:
--   1 clock from input sample to output sample.
--
-- Reset:
--   resetn is active-low.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hsv2rgb is
  port (
    clk          : in  std_logic;
    resetn       : in  std_logic;

    i_valid      : in  std_logic;
    i_sof        : in  std_logic := '0';
    i_eol        : in  std_logic := '0';
    i_eof        : in  std_logic := '0';
    i_hue        : in  std_logic_vector(7 downto 0);
    i_saturation : in  std_logic_vector(7 downto 0);
    i_value      : in  std_logic_vector(7 downto 0);

    o_valid      : out std_logic;
    o_sof        : out std_logic;
    o_eol        : out std_logic;
    o_eof        : out std_logic;
    o_red        : out std_logic_vector(7 downto 0);
    o_green      : out std_logic_vector(7 downto 0);
    o_blue       : out std_logic_vector(7 downto 0)
  );
end entity hsv2rgb;

architecture rtl of hsv2rgb is

  function clamp_u8(x : integer) return std_logic_vector is
    variable y : integer;
  begin
    if x < 0 then
      y := 0;
    elsif x > 255 then
      y := 255;
    else
      y := x;
    end if;
    return std_logic_vector(to_unsigned(y, 8));
  end function;

begin

  p_hsv_to_rgb : process(clk)
    variable h_v       : integer range 0 to 255;
    variable s_v       : integer range 0 to 255;
    variable v_v       : integer range 0 to 255;
    variable h6_v      : integer range 0 to 1530;
    variable region_v  : integer range 0 to 5;
    variable fpart_v   : integer range 0 to 255;
    variable p_v       : integer range 0 to 255;
    variable q_v       : integer range 0 to 255;
    variable t_v       : integer range 0 to 255;
    variable sf_v      : integer range 0 to 255;
    variable s1mf_v    : integer range 0 to 255;
    variable red_v     : integer range 0 to 255;
    variable green_v   : integer range 0 to 255;
    variable blue_v    : integer range 0 to 255;
  begin
    if rising_edge(clk) then
      if resetn = '0' then
        o_valid <= '0';
        o_sof   <= '0';
        o_eol   <= '0';
        o_eof   <= '0';
        o_red   <= (others => '0');
        o_green <= (others => '0');
        o_blue  <= (others => '0');
      else
        h_v := to_integer(unsigned(i_hue));
        s_v := to_integer(unsigned(i_saturation));
        v_v := to_integer(unsigned(i_value));

        if s_v = 0 then
          red_v   := v_v;
          green_v := v_v;
          blue_v  := v_v;
        else
          -- region = floor((H * 6) / 256), fpart = fractional sector position.
          h6_v     := h_v * 6;
          region_v := h6_v / 256;
          if region_v > 5 then
            region_v := 5;
          end if;
          fpart_v := h6_v - (region_v * 256);

          -- p/q/t use rounded divide-by-255 arithmetic for 8-bit HSV.
          p_v    := (v_v * (255 - s_v) + 127) / 255;
          sf_v   := (s_v * fpart_v + 127) / 255;
          q_v    := (v_v * (255 - sf_v) + 127) / 255;
          s1mf_v := (s_v * (255 - fpart_v) + 127) / 255;
          t_v    := (v_v * (255 - s1mf_v) + 127) / 255;

          case region_v is
            when 0 =>
              red_v   := v_v;
              green_v := t_v;
              blue_v  := p_v;
            when 1 =>
              red_v   := q_v;
              green_v := v_v;
              blue_v  := p_v;
            when 2 =>
              red_v   := p_v;
              green_v := v_v;
              blue_v  := t_v;
            when 3 =>
              red_v   := p_v;
              green_v := q_v;
              blue_v  := v_v;
            when 4 =>
              red_v   := t_v;
              green_v := p_v;
              blue_v  := v_v;
            when others =>
              red_v   := v_v;
              green_v := p_v;
              blue_v  := q_v;
          end case;
        end if;

        o_red   <= clamp_u8(red_v);
        o_green <= clamp_u8(green_v);
        o_blue  <= clamp_u8(blue_v);

        -- Video-control passthrough, aligned to the 1-clock data latency.
        o_valid <= i_valid;
        o_sof   <= i_sof;
        o_eol   <= i_eol;
        o_eof   <= i_eof;
      end if;
    end if;
  end process p_hsv_to_rgb;

end architecture rtl;
