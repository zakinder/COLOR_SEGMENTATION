-------------------------------------------------------------------------------
-- File        : div16_8_8.vhd
-- Description : Portable signed-divider block using only IEEE std_logic_1164
--               and numeric_std. This version is intentionally standalone and
--               does not use vendor-specific packages.
--
-- Default behavior:
--   a      : signed 17-bit numerator
--   b      : unsigned 8-bit denominator
--   result : signed 9-bit quotient
--
-- Latency:
--   1 clock when en = '1'. When en = '0', result holds its previous value.
--
-- Divide-by-zero:
--   Saturates result to the positive or negative signed limit.
--
-- Reset:
--   rstn is active-low.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity div16_8_8 is
  generic (
    a_width      : positive := 17;
    b_width      : positive := 8;
    result_width : positive := 9
  );
  port (
    clk    : in  std_logic;
    en     : in  std_logic;
    rstn   : in  std_logic;
    a      : in  std_logic_vector(a_width-1 downto 0);
    b      : in  std_logic_vector(b_width-1 downto 0);
    result : out std_logic_vector(result_width-1 downto 0)
  );
end entity div16_8_8;

architecture rtl of div16_8_8 is

  signal result_r : signed(result_width-1 downto 0) := (others => '0');

  function pow2(n : natural) return integer is
    variable v : integer := 1;
  begin
    for i in 1 to n loop
      v := v * 2;
    end loop;
    return v;
  end function;

  function clamp_signed(x : integer; width : positive) return signed is
    variable max_v : integer;
    variable min_v : integer;
    variable y     : integer;
  begin
    max_v := pow2(width - 1) - 1;
    min_v := -pow2(width - 1);

    if x > max_v then
      y := max_v;
    elsif x < min_v then
      y := min_v;
    else
      y := x;
    end if;

    return to_signed(y, width);
  end function;

begin

  p_divider : process(clk)
    variable num_v : integer;
    variable den_v : integer;
    variable quo_v : integer;
    variable max_q : integer;
    variable min_q : integer;
  begin
    if rising_edge(clk) then
      if rstn = '0' then
        result_r <= (others => '0');
      elsif en = '1' then
        num_v := to_integer(signed(a));
        den_v := to_integer(unsigned(b));
        max_q := pow2(result_width - 1) - 1;
        min_q := -pow2(result_width - 1);

        if den_v = 0 then
          if num_v < 0 then
            quo_v := min_q;
          else
            quo_v := max_q;
          end if;
        else
          quo_v := num_v / den_v;
        end if;

        result_r <= clamp_signed(quo_v, result_width);
      end if;
    end if;
  end process p_divider;

  result <= std_logic_vector(result_r);

end architecture rtl;
