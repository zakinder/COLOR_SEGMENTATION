-------------------------------------------------------------------------------
-- File        : tb_rgb_hsv2rgb_match_input_bmp.vhd
-- Description : Portable BMP-file testbench for RGB -> HSV -> RGB color-preserving round-trip.
--
-- Behavior:
--   1. Reads an uncompressed 24-bit BMP file from Input_Image/1000_500.bmp.
--   2. Loads the complete frame into simulation memory.
--   3. Streams the original RGB pixels into rgb_hsv without pre-filtering.
--   4. Feeds rgb_hsv output into hsv2rgb.
--   5. Writes reconstructed RGB pixels to Generated_Outputs/output_rgb_hsv2rgb_match_input.bmp.
--
-- Pipeline under test:
--   RGB BMP -> rgb_hsv -> hsv2rgb -> RGB BMP
--
-- Default spatial filter:
--   PREFILTER_MODE = 0, bypass. This keeps the input colors visually matched.
--
-- Optional spatial-filter mode values:
--   0 = bypass; no spatial filtering
--   1 = 3x3 box blur only
--   2 = 3x3 median only
--   3 = 3x3 median followed by 3x3 box blur
--
-- Notes:
--   * BMP pixel storage order is B, G, R.
--   * Supported BMP format: 24-bit BGR uncompressed BI_RGB BMP.
--   * This is a simulation/testbench pre-filter, not a synthesizable line-buffer
--     streaming filter. It intentionally reads the whole frame before streaming.
--   * Uses only IEEE std_logic_1164/numeric_std and binary character file I/O.
--   * resetn is active-low.
--   * Converter latency after the pre-filter is two clocks:
--       rgb_hsv = 1 clock
--       hsv2rgb = 1 clock
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rgb_hsv2rgb_match_input_bmp is
  generic (
    INPUT_BMP_FILE  : string := "Input_Image/1000_500.bmp";
    OUTPUT_BMP_FILE : string := "Generated_Outputs/output_rgb_hsv2rgb_match_input.bmp"
  );
end entity tb_rgb_hsv2rgb_match_input_bmp;

architecture sim of tb_rgb_hsv2rgb_match_input_bmp is

  constant CLK_PERIOD : time := 10 ns;

  -- This testbench package is sized for the supplied 1000x500 BMP.
  constant MAX_WIDTH  : integer := 1000;
  constant MAX_HEIGHT : integer := 500;
  constant MAX_PIXELS : integer := MAX_WIDTH * MAX_HEIGHT;

  -- 0 = bypass, 1 = box blur, 2 = median, 3 = median followed by box blur.
  constant PREFILTER_MODE : integer := 0;

  signal clk     : std_logic := '0';
  signal resetn  : std_logic := '0';
  signal tb_done : boolean   := false;

  -- RGB stream into rgb_hsv.
  signal i_valid : std_logic := '0';
  signal i_sof   : std_logic := '0';
  signal i_eol   : std_logic := '0';
  signal i_eof   : std_logic := '0';
  signal i_red   : std_logic_vector(7 downto 0) := (others => '0');
  signal i_green : std_logic_vector(7 downto 0) := (others => '0');
  signal i_blue  : std_logic_vector(7 downto 0) := (others => '0');
  signal i_alpha : std_logic_vector(7 downto 0) := (others => '1');

  -- Alpha delay path is retained internally; 24-bit input uses alpha=255.
  signal alpha_d1 : std_logic_vector(7 downto 0) := (others => '1');
  signal alpha_d2 : std_logic_vector(7 downto 0) := (others => '1');

  -- HSV stream between rgb_hsv and hsv2rgb.
  signal hsv_valid      : std_logic;
  signal hsv_sof        : std_logic;
  signal hsv_eol        : std_logic;
  signal hsv_eof        : std_logic;
  signal hsv_hue        : std_logic_vector(7 downto 0);
  signal hsv_saturation : std_logic_vector(7 downto 0);
  signal hsv_value      : std_logic_vector(7 downto 0);

  -- Reconstructed RGB output from hsv2rgb.
  signal rgb_valid : std_logic;
  signal rgb_sof   : std_logic;
  signal rgb_eol   : std_logic;
  signal rgb_eof   : std_logic;
  signal rgb_red   : std_logic_vector(7 downto 0);
  signal rgb_green : std_logic_vector(7 downto 0);
  signal rgb_blue  : std_logic_vector(7 downto 0);

  type char_file is file of character;
  type header_type is array (0 to 53) of integer range 0 to 255;
  type pixel_mem_t is array (0 to MAX_PIXELS - 1) of integer range 0 to 255;
  type int9_t is array (0 to 8) of integer range 0 to 255;

  function slv8_to_int(x : std_logic_vector(7 downto 0)) return integer is
  begin
    return to_integer(unsigned(x));
  end function;

  function le_u16(h : header_type; idx : natural) return integer is
  begin
    return h(idx) + (h(idx + 1) * 256);
  end function;

  function le_u32(h : header_type; idx : natural) return integer is
  begin
    return h(idx) +
           (h(idx + 1) * 256) +
           (h(idx + 2) * 65536) +
           (h(idx + 3) * 16777216);
  end function;

  function abs_i(x : integer) return integer is
  begin
    if x < 0 then
      return -x;
    else
      return x;
    end if;
  end function;

  function clamp_coord(v : integer; max_value : integer) return integer is
  begin
    if v < 0 then
      return 0;
    elsif v > max_value then
      return max_value;
    else
      return v;
    end if;
  end function;

  function get_pixel(
    constant mem          : pixel_mem_t;
    constant x            : integer;
    constant y            : integer;
    constant image_width  : integer;
    constant image_height : integer
  ) return integer is
    variable xx  : integer;
    variable yy  : integer;
    variable idx : integer;
  begin
    xx  := clamp_coord(x, image_width - 1);
    yy  := clamp_coord(y, image_height - 1);
    idx := (yy * image_width) + xx;
    return mem(idx);
  end function;

  function median9_from_frame(
    constant mem          : pixel_mem_t;
    constant x            : integer;
    constant y            : integer;
    constant image_width  : integer;
    constant image_height : integer
  ) return integer is
    variable a   : int9_t;
    variable t   : integer range 0 to 255;
    variable pos : integer;
  begin
    pos := 0;
    for yy in -1 to 1 loop
      for xx in -1 to 1 loop
        a(pos) := get_pixel(mem, x + xx, y + yy, image_width, image_height);
        pos := pos + 1;
      end loop;
    end loop;

    -- Small insertion/bubble sort for the nine neighborhood values.
    for i in 0 to 7 loop
      for j in i + 1 to 8 loop
        if a(j) < a(i) then
          t    := a(i);
          a(i) := a(j);
          a(j) := t;
        end if;
      end loop;
    end loop;

    return a(4);
  end function;

  function box9_from_frame(
    constant mem          : pixel_mem_t;
    constant x            : integer;
    constant y            : integer;
    constant image_width  : integer;
    constant image_height : integer
  ) return integer is
    variable sum_v : integer := 0;
  begin
    sum_v := 0;
    for yy in -1 to 1 loop
      for xx in -1 to 1 loop
        sum_v := sum_v + get_pixel(mem, x + xx, y + yy, image_width, image_height);
      end loop;
    end loop;

    return (sum_v + 4) / 9;
  end function;

  procedure build_median_frame(
    constant src          : in    pixel_mem_t;
    variable dst          : inout pixel_mem_t;
    constant image_width  : in    integer;
    constant image_height : in    integer
  ) is
    variable idx : integer;
  begin
    for y in 0 to image_height - 1 loop
      for x in 0 to image_width - 1 loop
        idx := (y * image_width) + x;
        dst(idx) := median9_from_frame(src, x, y, image_width, image_height);
      end loop;
    end loop;
  end procedure;

begin

  p_clk : process
  begin
    while not tb_done loop
      clk <= '0';
      wait for CLK_PERIOD / 2;
      clk <= '1';
      wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process p_clk;

  u_rgb_hsv : entity work.rgb_hsv
    port map (
      clk          => clk,
      resetn       => resetn,
      i_valid      => i_valid,
      i_sof        => i_sof,
      i_eol        => i_eol,
      i_eof        => i_eof,
      i_red        => i_red,
      i_green      => i_green,
      i_blue       => i_blue,
      o_valid      => hsv_valid,
      o_sof        => hsv_sof,
      o_eol        => hsv_eol,
      o_eof        => hsv_eof,
      o_hue        => hsv_hue,
      o_saturation => hsv_saturation,
      o_value      => hsv_value
    );

  u_hsv2rgb : entity work.hsv2rgb
    port map (
      clk          => clk,
      resetn       => resetn,
      i_valid      => hsv_valid,
      i_sof        => hsv_sof,
      i_eol        => hsv_eol,
      i_eof        => hsv_eof,
      i_hue        => hsv_hue,
      i_saturation => hsv_saturation,
      i_value      => hsv_value,
      o_valid      => rgb_valid,
      o_sof        => rgb_sof,
      o_eol        => rgb_eol,
      o_eof        => rgb_eof,
      o_red        => rgb_red,
      o_green      => rgb_green,
      o_blue       => rgb_blue
    );

  p_alpha_pipe : process(clk)
  begin
    if rising_edge(clk) then
      if resetn = '0' then
        alpha_d1 <= (others => '1');
        alpha_d2 <= (others => '1');
      else
        alpha_d1 <= i_alpha;
        alpha_d2 <= alpha_d1;
      end if;
    end if;
  end process p_alpha_pipe;

  p_stimulus : process
    file bmp_in  : char_file open read_mode  is INPUT_BMP_FILE;
    file bmp_out : char_file open write_mode is OUTPUT_BMP_FILE;

    variable header       : header_type;
    variable c            : character;
    variable data_offset  : integer;
    variable dib_size     : integer;
    variable width        : integer;
    variable height_raw   : integer;
    variable height_abs   : integer;
    variable planes       : integer;
    variable bits_pixel   : integer;
    variable bytes_pixel  : integer;
    variable compression  : integer;
    variable padding      : integer;
    variable b_in         : integer range 0 to 255;
    variable g_in         : integer range 0 to 255;
    variable r_in         : integer range 0 to 255;
    variable a_in         : integer range 0 to 255;
    variable pix_idx      : integer;
    variable r_filtered   : integer range 0 to 255;
    variable g_filtered   : integer range 0 to 255;
    variable b_filtered   : integer range 0 to 255;
    variable input_count  : integer := 0;
    variable output_count : integer := 0;
    variable total_pixels : integer := 0;

    variable red_src      : pixel_mem_t;
    variable green_src    : pixel_mem_t;
    variable blue_src     : pixel_mem_t;
    variable alpha_src    : pixel_mem_t;
    variable red_med      : pixel_mem_t;
    variable green_med    : pixel_mem_t;
    variable blue_med     : pixel_mem_t;

    procedure read_u8(file f : char_file; variable v : out integer) is
      variable ch : character;
    begin
      read(f, ch);
      v := character'pos(ch);
    end procedure;

    procedure write_u8(file f : char_file; constant v : in integer) is
    begin
      write(f, character'val(v));
    end procedure;

    procedure read_write_u8(file fin : char_file; file fout : char_file) is
      variable ch : character;
    begin
      read(fin, ch);
      write(fout, ch);
    end procedure;

    procedure write_zero_padding(file fout : char_file; constant n : in integer) is
    begin
      for p in 1 to n loop
        write(fout, character'val(0));
      end loop;
    end procedure;

    procedure write_rgb_output_if_valid(
      file fout                  : char_file;
      variable out_count         : inout integer;
      constant total_pixel_count : in integer;
      constant image_width       : in integer;
      constant row_padding       : in integer;
      constant byte_count_pixel  : in integer;
      constant alpha_value       : in integer
    ) is
    begin
      if rgb_valid = '1' and out_count < total_pixel_count then
        -- BMP byte order is B, G, R.
        write_u8(fout, slv8_to_int(rgb_blue));
        write_u8(fout, slv8_to_int(rgb_green));
        write_u8(fout, slv8_to_int(rgb_red));
        if byte_count_pixel = 4 then
          write_u8(fout, alpha_value);
        end if;

        out_count := out_count + 1;

        if (out_count mod image_width) = 0 then
          write_zero_padding(fout, row_padding);
        end if;
      end if;
    end procedure;

  begin
    ---------------------------------------------------------------------------
    -- Reset DUT chain.
    ---------------------------------------------------------------------------
    resetn  <= '0';
    i_valid <= '0';
    i_sof   <= '0';
    i_eol   <= '0';
    i_eof   <= '0';
    i_red   <= (others => '0');
    i_green <= (others => '0');
    i_blue  <= (others => '0');
    i_alpha <= (others => '1');

    for n in 0 to 4 loop
      wait until rising_edge(clk);
    end loop;

    resetn <= '1';
    wait until rising_edge(clk);
    wait for 0 ns;

    ---------------------------------------------------------------------------
    -- Read and copy the 54-byte BMP header.
    ---------------------------------------------------------------------------
    for i in header'range loop
      read_u8(bmp_in, header(i));
      write_u8(bmp_out, header(i));
    end loop;

    assert header(0) = character'pos('B') and header(1) = character'pos('M')
      report "Input file is not a BMP file: missing BM signature." severity failure;

    data_offset := le_u32(header, 10);
    dib_size    := le_u32(header, 14);
    width       := le_u32(header, 18);
    height_raw  := le_u32(header, 22);
    planes      := le_u16(header, 26);
    bits_pixel  := le_u16(header, 28);
    compression := le_u32(header, 30);

    assert dib_size = 40
      report "Unsupported BMP: DIB header size is not 40 bytes." severity failure;

    assert planes = 1
      report "Unsupported BMP: color planes is not 1." severity failure;

    assert bits_pixel = 24
      report "Unsupported BMP: only 24-bit BGR uncompressed BMP input is supported for this 1000x500 package." severity failure;

    assert compression = 0
      report "Unsupported BMP: compressed BMP input is not supported." severity failure;

    assert data_offset >= 54
      report "Unsupported BMP: pixel data offset is smaller than 54." severity failure;

    height_abs   := abs_i(height_raw);
    bytes_pixel  := bits_pixel / 8;
    padding      := (4 - ((width * bytes_pixel) mod 4)) mod 4;
    total_pixels := width * height_abs;

    assert width <= MAX_WIDTH and height_abs <= MAX_HEIGHT
      report "Input BMP is larger than this testbench memory limit. Increase MAX_WIDTH/MAX_HEIGHT." severity failure;

    report "Input BMP       : " & INPUT_BMP_FILE severity note;
    report "Output BMP      : " & OUTPUT_BMP_FILE severity note;
    report "Output mode     : RGB -> HSV -> RGB match-input-color round-trip" severity note;
    report "Prefilter mode  : " & integer'image(PREFILTER_MODE) & " 0=bypass, 1=blur, 2=median, 3=median+blur" severity note;
    report "BMP format      : " & integer'image(bits_pixel) & "-bit BI_RGB" severity note;
    report "Width           : " & integer'image(width) severity note;
    report "Height          : " & integer'image(height_abs) severity note;
    report "Total pixels    : " & integer'image(total_pixels) severity note;
    report "Row padding     : " & integer'image(padding) & " byte(s)" severity note;

    ---------------------------------------------------------------------------
    -- Copy optional bytes between the 54-byte header and the pixel array.
    ---------------------------------------------------------------------------
    if data_offset > 54 then
      for i in 54 to data_offset - 1 loop
        read_write_u8(bmp_in, bmp_out);
      end loop;
    end if;

    ---------------------------------------------------------------------------
    -- Load the whole BMP frame into simulation memory.
    -- Stored row order is preserved exactly as the BMP stores it.
    ---------------------------------------------------------------------------
    report "Loading BMP frame into simulation memory..." severity note;

    for y in 0 to height_abs - 1 loop
      for x in 0 to width - 1 loop
        pix_idx := (y * width) + x;

        read_u8(bmp_in, b_in);
        read_u8(bmp_in, g_in);
        read_u8(bmp_in, r_in);
        if bytes_pixel = 4 then
          read_u8(bmp_in, a_in);
        else
          a_in := 255;
        end if;

        red_src(pix_idx)   := r_in;
        green_src(pix_idx) := g_in;
        blue_src(pix_idx)  := b_in;
        alpha_src(pix_idx) := a_in;
        input_count := input_count + 1;
      end loop;

      -- Discard input BMP row padding. Output padding is generated when each
      -- output row is completed.
      for p in 1 to padding loop
        read(bmp_in, c);
      end loop;
    end loop;

    ---------------------------------------------------------------------------
    -- Build the optional median intermediate frame. The median stage removes
    -- isolated salt/pepper variations before HSV quantization.
    ---------------------------------------------------------------------------
    if PREFILTER_MODE = 3 then
      report "Building 3x3 median intermediate frame before 3x3 box blur..." severity note;
      build_median_frame(red_src,   red_med,   width, height_abs);
      build_median_frame(green_src, green_med, width, height_abs);
      build_median_frame(blue_src,  blue_med,  width, height_abs);
    end if;

    ---------------------------------------------------------------------------
    -- Stream RGB pixels through rgb_hsv -> hsv2rgb.
    ---------------------------------------------------------------------------
    report "Streaming RGB frame through rgb_hsv -> hsv2rgb..." severity note;

    for y in 0 to height_abs - 1 loop
      for x in 0 to width - 1 loop
        pix_idx := (y * width) + x;

        if PREFILTER_MODE = 0 then
          r_filtered := red_src(pix_idx);
          g_filtered := green_src(pix_idx);
          b_filtered := blue_src(pix_idx);
        elsif PREFILTER_MODE = 1 then
          r_filtered := box9_from_frame(red_src,   x, y, width, height_abs);
          g_filtered := box9_from_frame(green_src, x, y, width, height_abs);
          b_filtered := box9_from_frame(blue_src,  x, y, width, height_abs);
        elsif PREFILTER_MODE = 2 then
          r_filtered := median9_from_frame(red_src,   x, y, width, height_abs);
          g_filtered := median9_from_frame(green_src, x, y, width, height_abs);
          b_filtered := median9_from_frame(blue_src,  x, y, width, height_abs);
        else
          r_filtered := box9_from_frame(red_med,   x, y, width, height_abs);
          g_filtered := box9_from_frame(green_med, x, y, width, height_abs);
          b_filtered := box9_from_frame(blue_med,  x, y, width, height_abs);
        end if;

        i_red   <= std_logic_vector(to_unsigned(r_filtered, 8));
        i_green <= std_logic_vector(to_unsigned(g_filtered, 8));
        i_blue  <= std_logic_vector(to_unsigned(b_filtered, 8));
        i_alpha <= std_logic_vector(to_unsigned(alpha_src(pix_idx), 8));
        i_valid <= '1';
        i_sof   <= '1' when (x = 0 and y = 0) else '0';
        i_eol   <= '1' when (x = width - 1) else '0';
        i_eof   <= '1' when (x = width - 1 and y = height_abs - 1) else '0';

        wait until rising_edge(clk);
        wait for 0 ns;

        write_rgb_output_if_valid(bmp_out, output_count, total_pixels, width, padding, bytes_pixel, slv8_to_int(alpha_d2));
      end loop;
    end loop;

    ---------------------------------------------------------------------------
    -- Deassert input and flush the delayed rgb_hsv -> hsv2rgb output pixels.
    ---------------------------------------------------------------------------
    i_valid <= '0';
    i_sof   <= '0';
    i_eol   <= '0';
    i_eof   <= '0';
    i_red   <= (others => '0');
    i_green <= (others => '0');
    i_blue  <= (others => '0');
    i_alpha <= (others => '1');

    while output_count < total_pixels loop
      wait until rising_edge(clk);
      wait for 0 ns;
      write_rgb_output_if_valid(bmp_out, output_count, total_pixels, width, padding, bytes_pixel, slv8_to_int(alpha_d2));
    end loop;

    ---------------------------------------------------------------------------
    -- Copy any trailing bytes after the BMP pixel array, if present.
    ---------------------------------------------------------------------------
    while not endfile(bmp_in) loop
      read(bmp_in, c);
      write(bmp_out, c);
    end loop;

    ---------------------------------------------------------------------------
    -- Explicitly close the BMP files before stopping the simulation.
    -- This is important on some GHDL/Windows builds because binary character
    -- file output can remain buffered until file_close is called. Without this,
    -- the simulation may report success while the Generated_Outputs directory
    -- still appears empty from the batch file.
    ---------------------------------------------------------------------------
    file_close(bmp_out);
    file_close(bmp_in);

    report "Input pixels loaded  : " & integer'image(input_count) severity note;
    report "Output pixels written: " & integer'image(output_count) severity note;
    report "Output BMP closed    : " & OUTPUT_BMP_FILE severity note;
    report "tb_rgb_hsv2rgb_match_input_bmp completed successfully." severity note;

    tb_done <= true;
    wait;
  end process p_stimulus;

end architecture sim;
