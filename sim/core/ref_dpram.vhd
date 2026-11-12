-- Simulation model of the MiSTer BurgerTime core's dpram.vhd (an Altera
-- altsyncram wrapper, BIDIR_DUAL_PORT, unregistered outputs, new data on a
-- read during a write on the same port, powered up as zero). Used only to
-- simulate the unmodified upstream core in V1, compiled into library "ref".
-- Same entity and ports as upstream.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram is
	generic (
		 addr_width_g : integer := 8;
		 data_width_g : integer := 8
	);
	port
	(
		address_a	: in std_logic_vector (addr_width_g-1 downto 0);
		address_b	: in std_logic_vector (addr_width_g-1 downto 0);
		clock_a		: in std_logic  := '1';
		clock_b		: in std_logic ;
		data_a		: in std_logic_vector (data_width_g-1 downto 0);
		data_b		: in std_logic_vector (data_width_g-1 downto 0) := (others => '0');
		enable_a	: in std_logic  := '1';
		enable_b	: in std_logic  := '1';
		wren_a		: in std_logic  := '0';
		wren_b		: in std_logic  := '0';
		q_a			: out std_logic_vector (data_width_g-1 downto 0);
		q_b			: out std_logic_vector (data_width_g-1 downto 0)
	);
end dpram;

architecture sim of dpram is
	type ram_t is array(0 to 2**addr_width_g-1) of std_logic_vector(data_width_g-1 downto 0);
	signal ram : ram_t := (others => (others => '0'));
begin
	-- one process for both ports (in this core the two ports never write at
	-- the same time)
	process (clock_a, clock_b)
	begin
		if rising_edge(clock_a) and enable_a = '1' then
			if wren_a = '1' then
				ram(to_integer(unsigned(address_a))) <= data_a;
				q_a <= data_a;
			else
				q_a <= ram(to_integer(unsigned(address_a)));
			end if;
		end if;
		if rising_edge(clock_b) and enable_b = '1' then
			if wren_b = '1' then
				ram(to_integer(unsigned(address_b))) <= data_b;
				q_b <= data_b;
			else
				q_b <= ram(to_integer(unsigned(address_b)));
			end if;
		end if;
	end process;
end sim;
