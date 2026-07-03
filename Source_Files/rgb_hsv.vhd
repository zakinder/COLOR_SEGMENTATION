-------------------------------------------------------------------------------
-- File        : rgb_hsv.vhd
-- Description : Portable RGB-to-HSV converter using only IEEE std_logic_1164
--               and numeric_std. No project-specific channel records, fixed_pkg,
--               float_pkg, or external sync modules are required.
--
-- Color format:
--   Input : RGB, 8 bits/channel
--   Output: HSV, 8 bits/channel
--           o_hue        = 0..255 mapped around the hue circle
--           o_saturation = 0..255
--           o_value      = adjusted/flattened max(R,G,B), 0..255
--
-- Main use:
--   RGB input -> rgb_hsv -> hsv2rgb -> RGB output
--
-- Flat-color strategy:
--   1. Convert RGB to HSV.
--   2. Apply optional hue/saturation/value adjustment.
--   3. Suppress unstable hue in low-saturation pixels.
--   4. Force very dark pixels to black.
--   5. Quantize H/S/V into coarse bins.
--
-- Why this version is flatter:
--   Low-saturation pixels have unstable hue. If hue is quantized directly in
--   gray/shadow regions, small sensor/compression variations become colored
--   speckles. This version suppresses hue when saturation is low and snaps dark
--   pixels to black before final H/S/V quantization.
--
-- Important limitation:
--   This is still a pixel-local converter. It reduces palette noise, but it does
--   not perform spatial smoothing. For object-level flat regions, add a blur,
--   median filter, or region/cluster stage before this block.
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

entity rgb_hsv is
  port (
    clk          : in  std_logic;
    resetn       : in  std_logic;

    i_valid      : in  std_logic;
    i_sof        : in  std_logic := '0';
    i_eol        : in  std_logic := '0';
    i_eof        : in  std_logic := '0';
    i_red        : in  std_logic_vector(7 downto 0);
    i_green      : in  std_logic_vector(7 downto 0);
    i_blue       : in  std_logic_vector(7 downto 0);

    o_valid      : out std_logic;
    o_sof        : out std_logic;
    o_eol        : out std_logic;
    o_eof        : out std_logic;
    o_hue        : out std_logic_vector(7 downto 0);
    o_saturation : out std_logic_vector(7 downto 0);
    o_value      : out std_logic_vector(7 downto 0)
  );
end entity rgb_hsv;

architecture rtl of rgb_hsv is

  -----------------------------------------------------------------------------
  -- Hue adjustment control
  --
  -- Hue is circular. It wraps around 0..255 instead of clamping.
  --   0    = no hue shift
  --   16   = small color-family shift
  --   43   = about 60 degrees on the color wheel
  --   85   = about 120 degrees on the color wheel
  --   128  = near opposite-color / false-color shift
  -----------------------------------------------------------------------------
  constant HUE_OFFSET : integer := 0;

  -----------------------------------------------------------------------------
  -- Saturation/value adjustment controls
  --
  -- 100 = no gain change.
  -- >100 increases the channel. Example: 125 = +25%.
  -- <100 decreases the channel. Example: 75 = -25%.
  -- OFFSET constants add or subtract a final signed value after gain scaling.
  -- Final saturation/value results are clamped to 0..255.
  -----------------------------------------------------------------------------
  constant SATURATION_GAIN_PERCENT : integer := 125;
  constant SATURATION_OFFSET       : integer := 0;

  constant VALUE_GAIN_PERCENT      : integer := 125;
  constant VALUE_OFFSET            : integer := 10;

  -----------------------------------------------------------------------------
  -- Flat-color / posterization controls
  --
  -- Default is MATCH-INPUT-COLOR mode. Flat-color/posterization is disabled
  -- so RGB -> HSV -> RGB remains visually close to the input image.
  --
  -- More natural flat profile:
  --   HUE_STEP                  := 32
  --   SATURATION_STEP           := 64
  --   VALUE_STEP                := 85
  --   LOW_SATURATION_THRESHOLD  := 80
  --   LOW_VALUE_THRESHOLD       := 60
  --
  -- Strong total-flat profile:
  --   HUE_STEP                  := 64
  --   SATURATION_STEP           := 128
  --   VALUE_STEP                := 128
  --   LOW_SATURATION_THRESHOLD  := 96
  --   LOW_VALUE_THRESHOLD       := 64
  -----------------------------------------------------------------------------
  constant ENABLE_FLAT_COLOR       : boolean := true;
  constant HUE_STEP                : integer := 32;
  constant SATURATION_STEP         : integer := 32;
  constant VALUE_STEP              : integer := 16;
  constant FLAT_CENTER_BINS        : boolean := false;

  -----------------------------------------------------------------------------
  -- Noise/speckle guards for flatter output
  --
  -- LOW_SATURATION_TO_GRAY:
  --   When saturation is below LOW_SATURATION_THRESHOLD, hue is not reliable.
  --   The pixel is forced to neutral grayscale before value quantization.
  --
  -- LOW_VALUE_TO_BLACK:
  --   Very dark pixels often carry noisy hue/saturation due to small channel
  --   differences. These pixels are forced to black.
  --
  -- FORCE_COLORED_SATURATION:
  --   Optional. When true, all non-gray/non-black colored pixels use one fixed
  --   saturation value. This makes colors even flatter, but can look less
  --   natural on skin tones. Default false keeps more color balance.
  -----------------------------------------------------------------------------
  constant LOW_SATURATION_TO_GRAY      : boolean := false;
  constant LOW_SATURATION_THRESHOLD    : integer := 96;

  constant LOW_VALUE_TO_BLACK          : boolean := false;
  constant LOW_VALUE_THRESHOLD         : integer := 64;

  constant FORCE_COLORED_SATURATION    : boolean := false;
  constant FORCED_COLORED_SATURATION   : integer := 192;

  function max3(a : integer; b : integer; c : integer) return integer is
    variable m : integer;
  begin
    m := a;
    if b > m then
      m := b;
    end if;
    if c > m then
      m := c;
    end if;
    return m;
  end function;

  function min3(a : integer; b : integer; c : integer) return integer is
    variable m : integer;
  begin
    m := a;
    if b < m then
      m := b;
    end if;
    if c < m then
      m := c;
    end if;
    return m;
  end function;

  function clamp_int_u8(x : integer) return integer is
  begin
    if x < 0 then
      return 0;
    elsif x > 255 then
      return 255;
    else
      return x;
    end if;
  end function;

  function clamp_u8(x : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(clamp_int_u8(x), 8));
  end function;

  function wrap_int_u8(x : integer) return integer is
    variable y : integer;
  begin
    y := x;
    while y < 0 loop
      y := y + 256;
    end loop;
    while y > 255 loop
      y := y - 256;
    end loop;
    return y;
  end function;

  function adjust_u8(x : integer; gain_percent : integer; offset_value : integer) return integer is
    variable scaled_v   : integer;
    variable adjusted_v : integer;
  begin
    -- Rounded percent scaling followed by signed offset.
    if gain_percent >= 0 then
      scaled_v := ((x * gain_percent) + 50) / 100;
    else
      scaled_v := ((x * gain_percent) - 50) / 100;
    end if;

    adjusted_v := scaled_v + offset_value;
    return clamp_int_u8(adjusted_v);
  end function;

  function quantize_clamp_u8(x : integer; step_size : integer; center_bin : boolean) return integer is
    variable safe_step : integer;
    variable q_v       : integer;
  begin
    if step_size <= 1 then
      return clamp_int_u8(x);
    elsif step_size > 255 then
      safe_step := 255;
    else
      safe_step := step_size;
    end if;

    q_v := (clamp_int_u8(x) / safe_step) * safe_step;

    if center_bin then
      q_v := q_v + (safe_step / 2);
    end if;

    return clamp_int_u8(q_v);
  end function;

  function quantize_wrap_u8(x : integer; step_size : integer; center_bin : boolean) return integer is
    variable safe_step : integer;
    variable x_wrap    : integer;
    variable q_v       : integer;
  begin
    if step_size <= 1 then
      return wrap_int_u8(x);
    elsif step_size > 255 then
      safe_step := 255;
    else
      safe_step := step_size;
    end if;

    x_wrap := wrap_int_u8(x);
    q_v    := (x_wrap / safe_step) * safe_step;

    if center_bin then
      q_v := q_v + (safe_step / 2);
    end if;

    return wrap_int_u8(q_v);
  end function;

begin

  p_rgb_to_hsv : process(clk)
    variable r_v     : integer range 0 to 255;
    variable g_v     : integer range 0 to 255;
    variable b_v     : integer range 0 to 255;
    variable max_v   : integer range 0 to 255;
    variable min_v   : integer range 0 to 255;
    variable delta_v : integer range 0 to 255;
    variable hue_v   : integer;
    variable sat_v   : integer;
    variable value_v : integer;
    variable step_v  : integer;
  begin
    if rising_edge(clk) then
      if resetn = '0' then
        o_valid      <= '0';
        o_sof        <= '0';
        o_eol        <= '0';
        o_eof        <= '0';
        o_hue        <= (others => '0');
        o_saturation <= (others => '0');
        o_value      <= (others => '0');
      else
        r_v     := to_integer(unsigned(i_red));
        g_v     := to_integer(unsigned(i_green));
        b_v     := to_integer(unsigned(i_blue));
        max_v   := max3(r_v, g_v, b_v);
        min_v   := min3(r_v, g_v, b_v);
        delta_v := max_v - min_v;

        -----------------------------------------------------------------------
        -- Value calculation
        -----------------------------------------------------------------------
        value_v := adjust_u8(max_v, VALUE_GAIN_PERCENT, VALUE_OFFSET);

        -----------------------------------------------------------------------
        -- Saturation calculation
        -----------------------------------------------------------------------
        if max_v = 0 then
          sat_v := 0;
        else
          -- Rounded saturation: delta / max, scaled to 0..255.
          sat_v := ((delta_v * 255) + (max_v / 2)) / max_v;
        end if;
        sat_v := adjust_u8(sat_v, SATURATION_GAIN_PERCENT, SATURATION_OFFSET);

        -----------------------------------------------------------------------
        -- Hue calculation
        -----------------------------------------------------------------------
        if delta_v = 0 then
          hue_v := 0;
        elsif max_v = r_v then
          if g_v >= b_v then
            step_v := ((43 * (g_v - b_v)) + (delta_v / 2)) / delta_v;
            hue_v  := step_v;
          else
            step_v := ((43 * (b_v - g_v)) + (delta_v / 2)) / delta_v;
            hue_v  := 255 - step_v;
          end if;
        elsif max_v = g_v then
          if b_v >= r_v then
            step_v := ((43 * (b_v - r_v)) + (delta_v / 2)) / delta_v;
            hue_v  := 85 + step_v;
          else
            step_v := ((43 * (r_v - b_v)) + (delta_v / 2)) / delta_v;
            hue_v  := 85 - step_v;
          end if;
        else
          if r_v >= g_v then
            step_v := ((43 * (r_v - g_v)) + (delta_v / 2)) / delta_v;
            hue_v  := 171 + step_v;
          else
            step_v := ((43 * (g_v - r_v)) + (delta_v / 2)) / delta_v;
            hue_v  := 171 - step_v;
          end if;
        end if;

        -- Hue wraps because it is circular.
        hue_v := wrap_int_u8(hue_v + HUE_OFFSET);

        -----------------------------------------------------------------------
        -- Strong flat-color quantization stage
        -----------------------------------------------------------------------
        if ENABLE_FLAT_COLOR then

          -- Dark-pixel noise guard: avoid random colored shadows.
          if LOW_VALUE_TO_BLACK and (value_v <= LOW_VALUE_THRESHOLD) then
            hue_v   := 0;
            sat_v   := 0;
            value_v := 0;

          else
            -- Low-saturation guard: hue is unstable when RGB channels are close.
            if LOW_SATURATION_TO_GRAY and (sat_v <= LOW_SATURATION_THRESHOLD) then
              hue_v := 0;
              sat_v := 0;
            else
              hue_v := quantize_wrap_u8(hue_v, HUE_STEP, FLAT_CENTER_BINS);

              if FORCE_COLORED_SATURATION then
                sat_v := clamp_int_u8(FORCED_COLORED_SATURATION);
              else
                sat_v := quantize_clamp_u8(sat_v, SATURATION_STEP, FLAT_CENTER_BINS);
              end if;
            end if;

            -- Value is the most important channel for removing shading noise.
            value_v := quantize_clamp_u8(value_v, VALUE_STEP, FLAT_CENTER_BINS);
          end if;
        end if;

        o_hue        <= clamp_u8(hue_v);
        o_saturation <= clamp_u8(sat_v);
        o_value      <= clamp_u8(value_v);

        -- Video-control passthrough, aligned to the 1-clock data latency.
        o_valid <= i_valid;
        o_sof   <= i_sof;
        o_eol   <= i_eol;
        o_eof   <= i_eof;
      end if;
    end if;
  end process p_rgb_to_hsv;

end architecture rtl;
