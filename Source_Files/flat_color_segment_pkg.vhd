----------------------------------------------------------------------------------
-- File: flat_color_segment_pkg.vhd
-- Purpose:
--   Reusable flat-color segmentation helper package for BMP/GHDL validation.
--
-- Functions/procedures moved out of the testbench:
--   * 3x3 RGB median pre-filter helper
--   * General reference-color-preserving flat quantizer
--   * 3x3 majority post-filter helper
--
-- Pixel format:
--   rgb24_t = RED[23:16] & GREEN[15:8] & BLUE[7:0]
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package flat_color_segment_pkg is
    subtype rgb24_t is std_logic_vector(23 downto 0);
    type rgb_image_array_t is array (natural range <>) of rgb24_t;

    function flat_clip8(constant value : integer) return natural;

    function flat_make_rgb24(
        constant r8 : integer;
        constant g8 : integer;
        constant b8 : integer
    ) return rgb24_t;

    function flat_median9_scalar(
        constant p0 : integer;
        constant p1 : integer;
        constant p2 : integer;
        constant p3 : integer;
        constant p4 : integer;
        constant p5 : integer;
        constant p6 : integer;
        constant p7 : integer;
        constant p8 : integer
    ) return natural;

    function flat_rgb_to_hsv_segment(
        constant rgb24              : rgb24_t;
        constant sat_threshold_low  : integer;
        constant value_dark_limit   : integer;
        constant value_white_limit  : integer
    ) return rgb24_t;

    function flat_rgb_to_hsv_segment_xy(
        constant rgb24              : rgb24_t;
        constant pixel_x            : integer;
        constant pixel_y            : integer;
        constant sat_threshold_low  : integer;
        constant value_dark_limit   : integer;
        constant value_white_limit  : integer
    ) return rgb24_t;

    function flat_majority9_rgb24(
        constant p0                 : rgb24_t;
        constant p1                 : rgb24_t;
        constant p2                 : rgb24_t;
        constant p3                 : rgb24_t;
        constant p4                 : rgb24_t;
        constant p5                 : rgb24_t;
        constant p6                 : rgb24_t;
        constant p7                 : rgb24_t;
        constant p8                 : rgb24_t;
        constant majority_min_count : integer
    ) return rgb24_t;

    procedure flat_copy_image(
        constant source_image : in  rgb_image_array_t;
        variable target_image : out rgb_image_array_t
    );

    procedure flat_apply_median_filter(
        constant image_width  : in  integer;
        constant image_height : in  integer;
        constant source_image : in  rgb_image_array_t;
        variable target_image : out rgb_image_array_t
    );

    procedure flat_apply_hsv_segmentation(
        constant source_image        : in  rgb_image_array_t;
        variable target_image        : out rgb_image_array_t;
        constant sat_threshold_low   : in  integer;
        constant value_dark_limit    : in  integer;
        constant value_white_limit   : in  integer
    );

    procedure flat_apply_hsv_segmentation(
        constant image_width         : in  integer;
        constant image_height        : in  integer;
        constant source_image        : in  rgb_image_array_t;
        variable target_image        : out rgb_image_array_t;
        constant sat_threshold_low   : in  integer;
        constant value_dark_limit    : in  integer;
        constant value_white_limit   : in  integer
    );

    procedure flat_apply_majority_filter(
        constant image_width         : in  integer;
        constant image_height        : in  integer;
        constant source_image        : in  rgb_image_array_t;
        variable target_image        : out rgb_image_array_t;
        constant majority_min_count  : in  integer
    );
end package flat_color_segment_pkg;

package body flat_color_segment_pkg is
    type int9_array_t   is array (0 to 8) of integer;
    type rgb9_array_t   is array (0 to 8) of rgb24_t;

    function flat_max2(constant a : integer; constant b : integer) return integer is
    begin
        if a > b then
            return a;
        else
            return b;
        end if;
    end function;

    function flat_min2(constant a : integer; constant b : integer) return integer is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function;

    function flat_max3(
        constant a : integer;
        constant b : integer;
        constant c : integer
    ) return integer is
    begin
        return flat_max2(flat_max2(a, b), c);
    end function;

    function flat_min3(
        constant a : integer;
        constant b : integer;
        constant c : integer
    ) return integer is
    begin
        return flat_min2(flat_min2(a, b), c);
    end function;

    function flat_clip8(constant value : integer) return natural is
    begin
        if value < 0 then
            return 0;
        elsif value > 255 then
            return 255;
        else
            return natural(value);
        end if;
    end function;

    function flat_make_rgb24(
        constant r8 : integer;
        constant g8 : integer;
        constant b8 : integer
    ) return rgb24_t is
    begin
        return std_logic_vector(to_unsigned(flat_clip8(r8), 8)) &
               std_logic_vector(to_unsigned(flat_clip8(g8), 8)) &
               std_logic_vector(to_unsigned(flat_clip8(b8), 8));
    end function;
    function flat_quantize_rgb_channel(
        constant value8 : integer
    ) return natural is
        constant QUANT_STEP : integer := 16;
        variable q8         : integer;
    begin
        -- Round to the nearest 16-count level.  This keeps RGB-cube / expected
        -- reference colors aligned while still giving a flat/posterized output.
        -- Examples: 0->0, 7->0, 8->16, 127->128, 248..255->255.
        q8 := ((value8 + (QUANT_STEP / 2)) / QUANT_STEP) * QUANT_STEP;

        if value8 >= (255 - (QUANT_STEP / 2) + 1) then
            q8 := 255;
        end if;

        return flat_clip8(q8);
    end function;

    function flat_quantize_rgb24(
        constant rgb24 : rgb24_t
    ) return rgb24_t is
        variable r8 : integer;
        variable g8 : integer;
        variable b8 : integer;
    begin
        r8 := to_integer(unsigned(rgb24(23 downto 16)));
        g8 := to_integer(unsigned(rgb24(15 downto 8)));
        b8 := to_integer(unsigned(rgb24(7 downto 0)));

        return std_logic_vector(to_unsigned(flat_quantize_rgb_channel(r8), 8)) &
               std_logic_vector(to_unsigned(flat_quantize_rgb_channel(g8), 8)) &
               std_logic_vector(to_unsigned(flat_quantize_rgb_channel(b8), 8));
    end function;


    function flat_get_rgb_pixel_clamped(
        constant image_width  : integer;
        constant image_height : integer;
        constant image_memory : rgb_image_array_t;
        constant x            : integer;
        constant y            : integer
    ) return rgb24_t is
        variable cx : integer := x;
        variable cy : integer := y;
    begin
        if cx < 0 then
            cx := 0;
        elsif cx >= image_width then
            cx := image_width - 1;
        end if;

        if cy < 0 then
            cy := 0;
        elsif cy >= image_height then
            cy := image_height - 1;
        end if;

        return image_memory(image_memory'low + (cy * image_width) + cx);
    end function;

    function flat_get_channel8_clamped(
        constant image_width  : integer;
        constant image_height : integer;
        constant image_memory : rgb_image_array_t;
        constant x            : integer;
        constant y            : integer;
        constant channel_sel  : integer
    ) return integer is
        variable rgb24 : rgb24_t;
    begin
        rgb24 := flat_get_rgb_pixel_clamped(image_width, image_height, image_memory, x, y);

        if channel_sel = 0 then
            return to_integer(unsigned(rgb24(23 downto 16)));
        elsif channel_sel = 1 then
            return to_integer(unsigned(rgb24(15 downto 8)));
        else
            return to_integer(unsigned(rgb24(7 downto 0)));
        end if;
    end function;

    function flat_median9_scalar(
        constant p0 : integer;
        constant p1 : integer;
        constant p2 : integer;
        constant p3 : integer;
        constant p4 : integer;
        constant p5 : integer;
        constant p6 : integer;
        constant p7 : integer;
        constant p8 : integer
    ) return natural is
        variable values : int9_array_t := (p0, p1, p2, p3, p4, p5, p6, p7, p8);
        variable temp   : integer;
    begin
        for i in 0 to 7 loop
            for j in i + 1 to 8 loop
                if values(j) < values(i) then
                    temp      := values(i);
                    values(i) := values(j);
                    values(j) := temp;
                end if;
            end loop;
        end loop;

        return flat_clip8(values(4));
    end function;

    function flat_rgb_to_hsv_segment(
        constant rgb24              : rgb24_t;
        constant sat_threshold_low  : integer;
        constant value_dark_limit   : integer;
        constant value_white_limit  : integer
    ) return rgb24_t is
    begin
        ---------------------------------------------------------------------------
        -- General expected-reference color-match path.
        --
        -- Previous versions used a fixed hue palette and object-specific warm
        -- skin/sofa/cap overrides.  That was useful for one portrait frame, but it
        -- does not generalize to RGB reference images.  For a general testbench
        -- package, preserve the input RGB color family and only posterize each
        -- channel to a deterministic 16-count level.
        --
        -- The existing control parameters remain in the function signature for
        -- backward compatibility with the testbench generics and output filename.
        -- They are intentionally not used in this reference-match quantizer.
        ---------------------------------------------------------------------------
        return flat_quantize_rgb24(rgb24);
    end function;


    function flat_rgb_to_hsv_segment_xy(
        constant rgb24              : rgb24_t;
        constant pixel_x            : integer;
        constant pixel_y            : integer;
        constant sat_threshold_low  : integer;
        constant value_dark_limit   : integer;
        constant value_white_limit  : integer
    ) return rgb24_t is
    begin
        ---------------------------------------------------------------------------
        -- General XY wrapper.
        --
        -- No ROI, no image-size dependency, and no object-position assumptions.
        -- pixel_x and pixel_y are kept only to preserve the existing API.
        ---------------------------------------------------------------------------
        return flat_rgb_to_hsv_segment(
            rgb24,
            sat_threshold_low,
            value_dark_limit,
            value_white_limit
        );
    end function;


    function flat_majority9_rgb24(
        constant p0                 : rgb24_t;
        constant p1                 : rgb24_t;
        constant p2                 : rgb24_t;
        constant p3                 : rgb24_t;
        constant p4                 : rgb24_t;
        constant p5                 : rgb24_t;
        constant p6                 : rgb24_t;
        constant p7                 : rgb24_t;
        constant p8                 : rgb24_t;
        constant majority_min_count : integer
    ) return rgb24_t is
        variable pixels        : rgb9_array_t := (p0, p1, p2, p3, p4, p5, p6, p7, p8);
        variable center_pixel  : rgb24_t := p4;
        variable best_pixel    : rgb24_t := p4;
        variable current_count : integer;
        variable best_count    : integer := 0;
    begin
        for i in 0 to 8 loop
            current_count := 0;

            for j in 0 to 8 loop
                if pixels(j) = pixels(i) then
                    current_count := current_count + 1;
                end if;
            end loop;

            if (current_count > best_count) or
               ((current_count = best_count) and (pixels(i) = center_pixel)) then
                best_count := current_count;
                best_pixel := pixels(i);
            end if;
        end loop;

        if best_count >= majority_min_count then
            return best_pixel;
        else
            return center_pixel;
        end if;
    end function;

    procedure flat_copy_image(
        constant source_image : in  rgb_image_array_t;
        variable target_image : out rgb_image_array_t
    ) is
    begin
        for i in source_image'range loop
            target_image(i) := source_image(i);
        end loop;
    end procedure;

    procedure flat_apply_median_filter(
        constant image_width  : in  integer;
        constant image_height : in  integer;
        constant source_image : in  rgb_image_array_t;
        variable target_image : out rgb_image_array_t
    ) is
        variable r8 : natural;
        variable g8 : natural;
        variable b8 : natural;
        variable idx: integer;
    begin
        for y in 0 to image_height - 1 loop
            for x in 0 to image_width - 1 loop
                r8 := flat_median9_scalar(
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y - 1, 0),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y - 1, 0),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y - 1, 0),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y,     0),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y,     0),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y,     0),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y + 1, 0),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y + 1, 0),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y + 1, 0)
                );

                g8 := flat_median9_scalar(
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y - 1, 1),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y - 1, 1),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y - 1, 1),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y,     1),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y,     1),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y,     1),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y + 1, 1),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y + 1, 1),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y + 1, 1)
                );

                b8 := flat_median9_scalar(
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y - 1, 2),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y - 1, 2),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y - 1, 2),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y,     2),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y,     2),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y,     2),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x - 1, y + 1, 2),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x,     y + 1, 2),
                    flat_get_channel8_clamped(image_width, image_height, source_image, x + 1, y + 1, 2)
                );

                idx := target_image'low + (y * image_width) + x;
                target_image(idx) := flat_make_rgb24(integer(r8), integer(g8), integer(b8));
            end loop;
        end loop;
    end procedure;

    procedure flat_apply_hsv_segmentation(
        constant source_image        : in  rgb_image_array_t;
        variable target_image        : out rgb_image_array_t;
        constant sat_threshold_low   : in  integer;
        constant value_dark_limit    : in  integer;
        constant value_white_limit   : in  integer
    ) is
    begin
        for i in source_image'range loop
            target_image(i) := flat_rgb_to_hsv_segment(
                source_image(i),
                sat_threshold_low,
                value_dark_limit,
                value_white_limit
            );
        end loop;
    end procedure;

    procedure flat_apply_hsv_segmentation(
        constant image_width         : in  integer;
        constant image_height        : in  integer;
        constant source_image        : in  rgb_image_array_t;
        variable target_image        : out rgb_image_array_t;
        constant sat_threshold_low   : in  integer;
        constant value_dark_limit    : in  integer;
        constant value_white_limit   : in  integer
    ) is
        variable pixel_x : integer;
        variable pixel_y : integer;
        variable index0  : integer;
    begin
        for y in 0 to image_height - 1 loop
            for x in 0 to image_width - 1 loop
                index0  := source_image'low + (y * image_width) + x;
                pixel_x := x;
                pixel_y := y;

                target_image(index0) := flat_rgb_to_hsv_segment_xy(
                    source_image(index0),
                    pixel_x,
                    pixel_y,
                    sat_threshold_low,
                    value_dark_limit,
                    value_white_limit
                );
            end loop;
        end loop;
    end procedure;


    procedure flat_apply_majority_filter(
        constant image_width         : in  integer;
        constant image_height        : in  integer;
        constant source_image        : in  rgb_image_array_t;
        variable target_image        : out rgb_image_array_t;
        constant majority_min_count  : in  integer
    ) is
        variable idx : integer;
    begin
        for y in 0 to image_height - 1 loop
            for x in 0 to image_width - 1 loop
                idx := target_image'low + (y * image_width) + x;
                target_image(idx) := flat_majority9_rgb24(
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x - 1, y - 1),
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x,     y - 1),
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x + 1, y - 1),
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x - 1, y),
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x,     y),
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x + 1, y),
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x - 1, y + 1),
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x,     y + 1),
                    flat_get_rgb_pixel_clamped(image_width, image_height, source_image, x + 1, y + 1),
                    majority_min_count
                );
            end loop;
        end loop;
    end procedure;
end package body flat_color_segment_pkg;
