#!/bin/sh
# V1: build and run the core equivalence testbench with GHDL (mcode or llvm).
#
# Usage: sim/core/run_v1.sh <upstream> <rom> [frames] [pause_test] [dump]
#   upstream    path to the MiSTer core (Arcade-BurgerTime_MiSTer); its rtl/ is
#               simulated unmodified (see the note on dpram below), with
#               sim/core/ref_dpram.vhd for its Altera dpram
#   rom         64 KB image from sim/core/build_rom.py
#   frames      frames to compare (default 600)
#   pause_test  true/false: also run a copy of the port with random pauses (default true)
#   dump        true/false: write stream.bin and audio.bin (default true)
#
# GHDL: set GHDL (default ghdl). Outputs go to sim/out/core/ (ignored by git).
set -e
[ $# -ge 2 ] || { sed -n '4,13p' "$0"; exit 1; }
UP=$(cd "$1" && pwd)
ROM=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
FRAMES=${3:-600}
PAUSE=${4:-true}
DUMP=${5:-true}
GHDL=${GHDL:-ghdl}

HERE=$(cd "$(dirname "$0")" && pwd)
RTL=$HERE/../../rtl
OUT=$HERE/../out/core
mkdir -p "$OUT/lib"
cd "$OUT/lib"

OPTS="--std=08 -fsynopsys -frelaxed -Wno-hide"
REF="$UP/rtl/cpu/T65_Pack.vhd $UP/rtl/cpu/T65_MCode.vhd $UP/rtl/cpu/T65_ALU.vhd $UP/rtl/cpu/T65.vhd
     $UP/rtl/YM2149_linmix_sep.vhd $UP/rtl/gen_ram.vhd $HERE/ref_dpram.vhd
     $OUT/ref_src/burger_time_sound.vhd $OUT/ref_src/burger_time.vhd"
CONV="$RTL/cpu/T65_Pack.vhd $RTL/cpu/T65_MCode.vhd $RTL/cpu/T65_ALU.vhd $RTL/cpu/T65.vhd
      $RTL/YM2149_linmix_sep.vhd $RTL/gen_ram.vhd $RTL/dpram.vhd
      $RTL/burger_time_sound.vhd $RTL/burger_time.vhd"

# Three changes to the upstream sources, in a copy under sim/out/core/ref_src/:
# - upstream instantiates dpram as "label : work.dpram", which Quartus accepts
#   and GHDL does not: "entity" is added there.
# - the sound filter's integer registers get the initial value 0 that FPGA
#   registers power up with. GHDL starts an integer at the lowest value of its
#   range (-32768 for u3, u4), and the filter then overflows its range a few
#   samples after reset (a bound check failure). The port sets the same 0.
# - scroll1 and scroll2 get the initial value 0 too. BurgerTime never writes
#   scroll2 (0x4005), so in GHDL it stays 'U' and the background layer (floors
#   and ladders) is never drawn. The port sets the same 0.
mkdir -p "$OUT/ref_src"
for f in burger_time.vhd burger_time_sound.vhd; do
	sed -E -e 's/: *work\.dpram/: entity work.dpram/' \
	    -e 's/(signal (u3|u4|du3|du4|uout|uout_lim) +: integer range [^;]+);/\1 := 0;/' \
	    -e "s/(signal scroll[12] +: std_logic_vector\([0-9] downto 0\));/\\1 := (others => '0');/" \
	    "$UP/rtl/$f" > "$OUT/ref_src/$f"
done

rm -f *.cf
$GHDL -a $OPTS --work=ref $REF
$GHDL -a $OPTS --work=work $CONV $HERE/tb_v1.vhd
$GHDL -e $OPTS tb_v1
$GHDL -r $OPTS tb_v1 -gn_frames="$FRAMES" -gpause_test="$PAUSE" -gdump="$DUMP" \
	-grom_file="$ROM" -gout_dir="$OUT" --ieee-asserts=disable --max-stack-alloc=0 | tee "$OUT/v1_log.txt"
