-- V1, core equivalence: the unmodified MiSTer BurgerTime core (library ref,
-- 12 MHz clock) and the TangCore port of it (library work, 48 MHz clock with
-- enables) run side by side on the same ROM image and the same scripted
-- inputs. Every pixel (r, g, b, hs, vs, hblank, vblank, screen_flipped at each
-- pixel enable) and the audio output at every pixel enable must be identical.
--
-- A third instance of the port (pause_test) runs with its pause input
-- toggled at random (lengths 1 to 6000 clock_48 cycles): its output stream,
-- taken at its own pixel enables, must be identical too.
--
-- Generics: rom_file (64 KB image from build_rom.py), out_dir, n_frames,
-- pause_test, dump. With dump, the port's stream is written to
-- <out_dir>/stream.bin (2 bytes per pixel enable, from the first pixel after
-- reset; see frames.py) and the audio to <out_dir>/audio.bin (one 16-bit
-- little-endian sample per 256 pixel enables = per audio update, 23.4 kHz).
-- The result is printed and written to <out_dir>/v1_result.txt.
--
-- Scripted inputs, by frame (one frame = 384 x 272 pixel enables after reset):
-- coin 1 at frame c_coin, 1P start at c_start, then from c_play a repeating
-- joystick pattern with pepper presses. Each instance gets them right after
-- the first pixel of the frame, on its own timeline.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

library ref;

entity tb_v1 is
	generic (
		rom_file   : string  := "btime.rom";
		out_dir    : string  := ".";
		n_frames   : integer := 600;
		pause_test : boolean := true;
		dump       : boolean := true;
		c_coin     : integer := 200;
		c_start    : integer := 230;
		c_play     : integer := 260
	);
end tb_v1;

architecture sim of tb_v1 is

	constant FRAME : integer := 384 * 272;
	constant RING_N  : integer := 2**19;

	signal clk48    : std_logic := '0';
	signal clock_12 : std_logic := '0';
	signal tb_ph    : std_logic_vector(3 downto 0) := "1000"; -- as the port's phase
	signal done     : std_logic := '0';
	signal reset    : std_logic := '1';

	signal dn_addr  : std_logic_vector(16 downto 0) := (others => '0');
	signal dn_data  : std_logic_vector(7 downto 0) := (others => '0');
	signal dn_wr    : std_logic := '0';

	-- inputs: 0 start1, 1 start2, 2 coin1, 3 coin2, 4 fire1, 5 right1, 6 left1,
	-- 7 down1, 8 up1, 9 fire2, 10 right2, 11 left2, 12 down2, 13 up2
	signal in_ref, in_cv, in_cp : std_logic_vector(13 downto 0) := (others => '0');
	signal pause_cp : std_logic := '0';

	constant dip1 : std_logic_vector(7 downto 0) := x"00" xor x"3F"; -- MRA default 00,14
	constant dip2 : std_logic_vector(7 downto 0) := not x"14";

	type outs_t is record
		ce : std_logic;
		r, g : std_logic_vector(2 downto 0);
		b : std_logic_vector(1 downto 0);
		hs, vs, hb, vb, cs, fl : std_logic;
		audio : std_logic_vector(10 downto 0);
	end record;
	signal o_ref, o_cv, o_cp : outs_t;

	function pack(o : outs_t) return std_logic_vector is
	begin
		return o.fl & o.vs & o.hs & o.vb & o.hb & o.r & o.g & o.b & o.audio;
	end function;

	function script(f : integer) return std_logic_vector is
		variable v : std_logic_vector(13 downto 0) := (others => '0');
		variable t : integer;
	begin
		if f >= c_coin and f < c_coin + 6 then v(2) := '1'; end if;
		if f >= c_start and f < c_start + 6 then v(0) := '1'; end if;
		if f >= c_play then
			t := (f - c_play) mod 240;
			if    t < 60  then v(5) := '1'; -- right
			elsif t < 90  then v(8) := '1'; -- up
			elsif t < 150 then v(6) := '1'; -- left
			elsif t < 180 then v(7) := '1'; -- down
			end if;
			if (f - c_play) mod 40 >= 30 and (f - c_play) mod 40 < 34 then
				v(4) := '1';                    -- pepper
			end if;
		end if;
		return v;
	end function;

	-- bits as characters (keeps U and X visible)
	function hex(v : std_logic_vector) return string is
		variable str : string(1 to v'length);
		variable k : integer := 1;
		variable im : string(1 to 3);
	begin
		for i in v'range loop
			im := std_logic'image(v(i));
			str(k) := im(2);
			k := k + 1;
		end loop;
		return str;
	end function;

	function b01(s : std_logic) return integer is
	begin
		if s = '1' or s = 'H' then return 1; else return 0; end if;
	end function;

	function u01(v : std_logic_vector) return integer is
		variable n : integer := 0;
	begin
		for i in v'range loop n := n * 2 + b01(v(i)); end loop;
		return n;
	end function;

begin

	-- 48 MHz (period 20 ns in simulation time) and the reference's 12 MHz,
	-- whose rising edges are the clock_48 edges where the port has ce12.
	process
	begin
		while done = '0' loop
			clk48 <= '1'; wait for 10 ns;
			clk48 <= '0'; wait for 10 ns;
		end loop;
		wait;
	end process;

	process (clk48)
	begin
		if rising_edge(clk48) then
			tb_ph <= tb_ph(2 downto 0) & tb_ph(3);
			if tb_ph(0) = '1' then
				clock_12 <= '1';
			elsif tb_ph(2) = '1' then
				clock_12 <= '0';
			end if;
		end if;
	end process;

	u_ref : entity ref.burger_time
	port map (
		clock_12 => clock_12, reset => reset,
		dn_addr => dn_addr, dn_data => dn_data, dn_wr => dn_wr,
		video_ce => o_ref.ce, video_r => o_ref.r, video_g => o_ref.g, video_b => o_ref.b,
		video_hs => o_ref.hs, video_vs => o_ref.vs, video_vblank => o_ref.vb,
		video_hblank => o_ref.hb, video_csync => o_ref.cs, audio_out => o_ref.audio,
		start1 => in_ref(0), start2 => in_ref(1), coin1 => in_ref(2), coin2 => in_ref(3),
		fire1 => in_ref(4), right1 => in_ref(5), left1 => in_ref(6), down1 => in_ref(7), up1 => in_ref(8),
		fire2 => in_ref(9), right2 => in_ref(10), left2 => in_ref(11), down2 => in_ref(12), up2 => in_ref(13),
		dip_sw1 => dip1, dip_sw2 => dip2,
		dbg_cpu_addr => open,
		hs_address => (others => '0'), hs_data_out => open, hs_data_in => (others => '0'), hs_write => '0',
		pause => '0', flip_screen => '0', orig_vtiming => '1', cpu_speed => '1',
		screen_flipped_o => o_ref.fl
	);

	u_cv : entity work.burger_time
	port map (
		clock_48 => clk48, reset => reset, pause => '0',
		dn_addr => dn_addr, dn_data => dn_data, dn_wr => dn_wr,
		video_ce => o_cv.ce, video_r => o_cv.r, video_g => o_cv.g, video_b => o_cv.b,
		video_hs => o_cv.hs, video_vs => o_cv.vs, video_vblank => o_cv.vb,
		video_hblank => o_cv.hb, video_csync => o_cv.cs, audio_out => o_cv.audio,
		start1 => in_cv(0), start2 => in_cv(1), coin1 => in_cv(2), coin2 => in_cv(3),
		fire1 => in_cv(4), right1 => in_cv(5), left1 => in_cv(6), down1 => in_cv(7), up1 => in_cv(8),
		fire2 => in_cv(9), right2 => in_cv(10), left2 => in_cv(11), down2 => in_cv(12), up2 => in_cv(13),
		dip_sw1 => dip1, dip_sw2 => dip2,
		screen_flipped_o => o_cv.fl
	);

	g_cp : if pause_test generate
		u_cp : entity work.burger_time
		port map (
			clock_48 => clk48, reset => reset, pause => pause_cp,
			dn_addr => dn_addr, dn_data => dn_data, dn_wr => dn_wr,
			video_ce => o_cp.ce, video_r => o_cp.r, video_g => o_cp.g, video_b => o_cp.b,
			video_hs => o_cp.hs, video_vs => o_cp.vs, video_vblank => o_cp.vb,
			video_hblank => o_cp.hb, video_csync => o_cp.cs, audio_out => o_cp.audio,
			start1 => in_cp(0), start2 => in_cp(1), coin1 => in_cp(2), coin2 => in_cp(3),
			fire1 => in_cp(4), right1 => in_cp(5), left1 => in_cp(6), down1 => in_cp(7), up1 => in_cp(8),
			fire2 => in_cp(9), right2 => in_cp(10), left2 => in_cp(11), down2 => in_cp(12), up2 => in_cp(13),
			dip_sw1 => dip1, dip_sw2 => dip2,
			screen_flipped_o => o_cp.fl
		);
	end generate;

	g_no_cp : if not pause_test generate
		o_cp.ce <= '0';
	end generate;

	main : process
		type char_file is file of character;
		file rom_f : char_file;
		file str_f : char_file;
		file aud_f : char_file;
		file res_f : text;
		type rom_t is array(0 to 65535) of integer range 0 to 255;
		variable rom : rom_t;
		variable c : character;
		type ring_t is array(0 to RING_N-1) of std_logic_vector(23 downto 0);
		variable ring : ring_t;
		variable n_ref, n_cv, n_cp : integer := 0;
		variable n_total : integer;
		variable mm_cv_v, mm_cv_a, mm_cp_v, mm_cp_a : integer := 0;
		variable shown : integer := 0;
		variable s_ref, s : std_logic_vector(23 downto 0);
		variable pend_ref, pend_cv, pend_cp : boolean := false;
		variable pv_ref, pv_cv, pv_cp : std_logic_vector(13 downto 0);
		variable seed1, seed2 : positive := 12345;
		variable rnd : real;
		variable pause_cnt, gap_cnt : integer := 0;
		variable n_pauses, n_pause_cycles : integer := 0;
		variable max_lag : integer := 0;
		variable n_meta, first_meta, last_meta : integer := 0;
		variable l : line;
		variable pix : integer;

		procedure check(name : string; p : integer; s : std_logic_vector(23 downto 0);
		                variable mm_v, mm_a : inout integer) is
			variable r : std_logic_vector(23 downto 0);
			variable ll : line;
		begin
			r := ring(p mod RING_N);
			if s(23 downto 11) /= r(23 downto 11) then mm_v := mm_v + 1; end if;
			if s(10 downto 0) /= r(10 downto 0) then mm_a := mm_a + 1; end if;
			if s /= r and shown < 20 then
				shown := shown + 1;
				write(ll, name & " mismatch at pixel " & integer'image(p) &
					" (frame " & integer'image(p / FRAME) & ", line " & integer'image((p mod FRAME) / 384) &
					", pixel " & integer'image(p mod 384) & "): ref " & hex(r) & " port " & hex(s));
				writeline(output, ll);
			end if;
		end procedure;

		procedure wbyte(file f : char_file; v : integer) is
		begin
			write(f, character'val(v mod 256));
		end procedure;
	begin
		n_total := n_frames * FRAME;

		-- ROM image
		file_open(rom_f, rom_file, read_mode);
		for i in 0 to 65535 loop
			read(rom_f, c);
			rom(i) := character'pos(c);
		end loop;
		file_close(rom_f);
		if dump then
			file_open(str_f, out_dir & "/stream.bin", write_mode);
			file_open(aud_f, out_dir & "/audio.bin", write_mode);
		end if;

		-- download under reset: one byte per 12 MHz cycle, changed on clock_12
		-- falling (the reference writes on clock_12 rising, the port on every
		-- clock_48 cycle with dn_wr)
		for i in 0 to 65535 loop
			wait until rising_edge(clk48) and tb_ph(2) = '1';
			dn_addr <= std_logic_vector(to_unsigned(i, 17));
			dn_data <= std_logic_vector(to_unsigned(rom(i), 8));
			dn_wr <= '1';
		end loop;
		wait until rising_edge(clk48) and tb_ph(2) = '1';
		dn_wr <= '0';
		for i in 0 to 400 loop
			wait until rising_edge(clk48);
		end loop;
		wait until rising_edge(clk48) and tb_ph(3) = '1';
		reset <= '0';

		loop
			wait until rising_edge(clk48);

			-- inputs found at the first pixel of a frame, applied one clock_48
			-- cycle later (no instance samples inputs on that cycle)
			if pend_ref then in_ref <= pv_ref; pend_ref := false; end if;
			if pend_cv then in_cv <= pv_cv; pend_cv := false; end if;
			if pend_cp then in_cp <= pv_cp; pend_cp := false; end if;

			-- reference: pixel at the rising edge of clock_12 with clock_6 high
			if tb_ph(0) = '1' and o_ref.ce = '1' then
				ring(n_ref mod RING_N) := pack(o_ref);
				if n_ref mod FRAME = 0 then
					pv_ref := script(n_ref / FRAME); pend_ref := true;
					if (n_ref / FRAME) mod 50 = 0 then
						write(l, "frame " & integer'image(n_ref / FRAME) & " at " & time'image(now));
						writeline(output, l);
					end if;
				end if;
				n_ref := n_ref + 1;
			end if;

			-- port, lock-step
			if o_cv.ce = '1' then
				assert tb_ph(0) = '1' report "port pixel enable off phase" severity failure;
				s := pack(o_cv);
				if n_cv < n_total then
					assert n_cv < n_ref report "port ahead of reference" severity failure;
					check("port", n_cv, s, mm_cv_v, mm_cv_a);
					-- outputs not 0 or 1 (an undefined value in the simulation)
					if n_cv >= 2 * FRAME and is_x(s) then
						if n_meta = 0 then
							first_meta := n_cv;
							write(l, "first undefined output at pixel " & integer'image(n_cv) & ": " & hex(s) &
								" (flip vs hs vblank hblank r g b audio)");
							writeline(output, l);
						end if;
						n_meta := n_meta + 1;
						last_meta := n_cv;
					end if;
					if dump then
						wbyte(str_f, b01(s(18)) * 128 + b01(s(17)) * 64 + b01(s(16)) * 32 +
						             b01(s(15)) * 16 + b01(s(14)) * 8 + b01(s(13)) * 4 +
						             b01(s(12)) * 2 + b01(s(11)));
						wbyte(str_f, b01(s(19)) + b01(s(20)) * 2 + b01(s(21)) * 4 +
						             b01(s(22)) * 8 + b01(s(23)) * 16);
						if n_cv mod 256 = 0 then
							pix := u01(s(10 downto 0));
							wbyte(aud_f, pix mod 256);
							wbyte(aud_f, pix / 256);
						end if;
					end if;
				end if;
				if n_cv mod FRAME = 0 then
					pv_cv := script(n_cv / FRAME); pend_cv := true;
				end if;
				n_cv := n_cv + 1;
			end if;

			-- port with pauses
			if pause_test then
				if o_cp.ce = '1' then
					if n_cp < n_total then
						assert n_cp < n_ref report "paused port ahead of reference" severity failure;
						assert n_ref - n_cp < RING_N report "paused port too far behind" severity failure;
						check("paused port", n_cp, pack(o_cp), mm_cp_v, mm_cp_a);
					end if;
					if n_cp mod FRAME = 0 then
						pv_cp := script(n_cp / FRAME); pend_cp := true;
					end if;
					n_cp := n_cp + 1;
				end if;
				if n_ref - n_cp > max_lag then max_lag := n_ref - n_cp; end if;

				-- random pauses while the reference runs
				if pause_cnt > 0 then
					pause_cnt := pause_cnt - 1;
					n_pause_cycles := n_pause_cycles + 1;
					if pause_cnt = 0 then pause_cp <= '0'; end if;
				elsif gap_cnt > 0 then
					gap_cnt := gap_cnt - 1;
				elsif n_ref < n_total then
					uniform(seed1, seed2, rnd);
					if rnd < 0.5 then
						uniform(seed1, seed2, rnd);
						pause_cnt := 1 + integer(trunc(rnd * 16.0));
					else
						uniform(seed1, seed2, rnd);
						pause_cnt := 17 + integer(trunc(rnd * 6000.0));
					end if;
					uniform(seed1, seed2, rnd);
					gap_cnt := 1 + integer(trunc(rnd * 400000.0));
					if rnd < 0.1 then gap_cnt := 1 + integer(trunc(rnd * 100.0)); end if;
					n_pauses := n_pauses + 1;
					pause_cp <= '1';
				end if;
			end if;

			exit when n_cv >= n_total and (not pause_test or n_cp >= n_total);
		end loop;

		if dump then
			file_close(str_f);
			file_close(aud_f);
		end if;

		file_open(res_f, out_dir & "/v1_result.txt", write_mode);
		for k in 0 to 1 loop
			write(l, string'("V1 result"));
			if k = 0 then writeline(output, l); else writeline(res_f, l); end if;
			write(l, "frames: " & integer'image(n_frames) & " (" & integer'image(FRAME) & " pixel enables each)");
			if k = 0 then writeline(output, l); else writeline(res_f, l); end if;
			write(l, "port: pixels compared " & integer'image(n_total) &
				", video mismatches " & integer'image(mm_cv_v) &
				", audio values compared " & integer'image(n_total) &
				" (audio samples " & integer'image(n_total / 256) & ")" &
				", audio mismatches " & integer'image(mm_cv_a));
			if k = 0 then writeline(output, l); else writeline(res_f, l); end if;
			write(l, "port: outputs with undefined bits (U, X) from frame 2 on: " & integer'image(n_meta) &
				" (first at pixel " & integer'image(first_meta) & ", frame " & integer'image(first_meta / FRAME) &
				"; last at pixel " & integer'image(last_meta) & ", frame " & integer'image(last_meta / FRAME) & ")");
			if k = 0 then writeline(output, l); else writeline(res_f, l); end if;
			if pause_test then
				write(l, "paused port: pixels compared " & integer'image(n_total) &
					", video mismatches " & integer'image(mm_cp_v) &
					", audio mismatches " & integer'image(mm_cp_a) &
					", pauses " & integer'image(n_pauses) &
					", paused clock_48 cycles " & integer'image(n_pause_cycles) &
					", max lag " & integer'image(max_lag) & " pixels");
				if k = 0 then writeline(output, l); else writeline(res_f, l); end if;
			end if;
			if mm_cv_v + mm_cv_a + mm_cp_v + mm_cp_a = 0 then
				write(l, string'("PASS"));
			else
				write(l, string'("FAIL"));
			end if;
			if k = 0 then writeline(output, l); else writeline(res_f, l); end if;
		end loop;
		file_close(res_f);

		done <= '1';
		wait;
	end process;

end sim;
