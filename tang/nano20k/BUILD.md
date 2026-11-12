# BurgerTime on the Sipeed Tang Nano 20K

A port of the MiSTer BurgerTime core to the Sipeed Tang Nano 20K (GW2AR-LV18QN88C8/I7), as a
[TangCore](https://github.com/nand2mario/tangcore) core. The TangCore BL616 firmware loads the
core from the USB drive, shows the menu and sends the game's ROMs to the core over its UART.
Video and sound go out over the HDMI port at 1280x720, 60 Hz. The picture goes through a frame
buffer in the embedded SDRAM, which lets it be shown rotated, as on the original upright cabinet.

## Status

- Simulated: the core against the unmodified MiSTer core, cycle for cycle (V1 in
  `port_plan.md`), and the frame buffer with the core's recorded pictures (V2).
- Not yet tried on the board.

## Files

All under `tang/nano20k/` unless noted.

| File | Purpose |
|---|---|
| `build.tcl` (repository root) | `gw_sh` build script |
| `top.sv` | Top level: PLLs, iosys, ROM loading, core, gamepads, frame buffer, audio, HDMI, LEDs |
| `rom_stream.sv` | Writes the ROM image from the firmware into the core's block RAM (`dn_*` port) |
| `framebuffer.sv` | Frame buffer: `fb_writer.sv`, `fb_reader.sv` and `sdram.v`, with the SDRAM arbiter |
| `fb_writer.sv` | Core pixels into one of three buffers in SDRAM, rotated or not |
| `fb_reader.sv` | Latest finished buffer to the 1280x720 HDMI picture, scaled and centred, with the menu overlay |
| `sdram.v` | Controller for the GW2AR's embedded 8 MB SDRAM (32 MHz, one access at a time, byte or 32-bit word) |
| `gowin_pll_game.v` | Game PLL: 27 MHz in, 48 MHz and 32 MHz out |
| `gowin_pll_hdmi.v` | HDMI PLL: 27 MHz in, 371.25 MHz out (divided by 5 to 74.25 MHz in `top.sv`) |
| `nano20k.cst` | Pin constraints (clock, S1, LEDs, HDMI, UART, gamepads). The SDRAM is placed by the tool |
| `burgertime.sdc` | Timing constraints |
| `iosys/` | TangCore IO system: `iosys_bl616.v`, `textdisp.v`, `uart_fixed.v` (copies of `fpga_tangcore/common/iosys`, kept in step by `scripts/sync_common.sh`) and `gowin_dpb_menu.v` (menu font and this core's logo, written by `scripts/font_glyphs.py`) |
| `controller_snes.v`, `controller_ds2.sv`, `dualshock_controller.v` | SNES and DualShock pads on the board's pins, from TangCore's nestang |
| `hdmi/` | HDMI encoder from hdl-util by Sameer Puri, MIT OR Apache-2.0 (licence files in `hdmi/`). Local changes are listed at the top of `hdmi/hdmi.sv` |

The core is in `rtl/` (VHDL): `burger_time.vhd`, `burger_time_sound.vhd`,
`YM2149_linmix_sep.vhd` (AY-3-8910), `cpu/` (T65, 6502), `gen_ram.vhd` and `dpram.vhd`
(memories written so Gowin maps them to block RAM). The changes from the MiSTer core are listed
at the top of each file. `sim/` has the simulations (`sim/core`: V1, GHDL; `sim/fb`: V2,
Verilator); their outputs go to `sim/out/`, which git ignores.

## Build

You need the Gowin IDE or its command-line `gw_sh`, version 1.9.11.03. The Education edition
works. From the repository root:

```sh
/path/to/gowin/IDE/bin/gw_sh build.tcl nano20k
```

The core is written to `impl/pnr/burgertime_nano20k.bin` (and `.fs`). Reports are in
`impl/gwsynthesis/` and `impl/pnr/`. A build takes a few minutes.

On a Linux machine without a display, `gw_sh` can fail to start with a Qt "xcb" error. Set
`QT_QPA_PLATFORM=offscreen` before running it.

`burgertime.sdc` declares the four real clocks (27 MHz input, 48 and 32 MHz game, 74.25 MHz
HDMI). The 48 and 32 MHz clocks come from one PLL and are timed against each other; the HDMI
clock comes from another PLL and the tool does not time paths between it and the game clocks.
The only other line is `set_false_path -to [get_regs {*_meta*}]`: a register named `*_meta` is
the first flop of a two-flop synchroniser, where the crossing is on purpose and the value is
used only after the second flop. They are iosys's UART input; in `top.sv` the core reset, the
menu state, the controls and the DIP switches into the 48 MHz clock and the core's audio into
the HDMI clock; in `rom_stream.sv` the download handshake (both ways); in `fb_writer.sv` and
`fb_reader.sv` the frame buffer's toggles and flags, the rotate option and the menu state; in
`hdmi.sv` the master volume. Gowin uses only one `.sdc`, so the line is in this one. Check
`impl/pnr/burgertime_nano20k_tr_content.html` ("Max Frequency Summary") after a change; all
clocks meet timing with place options 0, 1 and 2.

The design must not depend on placement. Two things here exist for that reason, keep them
when changing the code:

- `build.tcl` puts registers that connect straight to a pin into the I/O blocks
  (`-ireg_in_iob`, `-oreg_in_iob`, `-ioreg_in_iob`). `sdram.v` registers the 32-bit DQ bus
  with nothing in front of the register, and `top.sv` drives the SDRAM clock from an ODDR.
  Without this, some placements read bad data from SDRAM (in the System SJ port this showed
  as a white screen or stray pixels).
- Each block RAM is written and read on the same clock where both ports can meet: all the
  core's memories run on the 48 MHz clock (the download port too). The frame buffer's two
  dual-clock RAMs (the writer's staging lines, the reader's line buffer) are never read and
  written at the same address at the same time (see `fb_writer.sv`, `fb_reader.sv`).

A quick check after a change: build with `-place_option` 0, 1 and 2 (`build.tcl` uses 2) and
run the game on each. All three should be free of stray pixels.

## Installing on the TangCore USB drive

| Path on the drive | What |
|---|---|
| `cores/nano20k/burgertime.bin` | The core: `impl/pnr/burgertime_nano20k.bin` renamed |
| `arcade/Burger Time (Set 1).mra` | The game: the `.mra` from `releases/` |
| `arcade/mame/btime.zip` | Your MAME ROM set for BurgerTime (`btime`) |

The TangCore firmware must be a version that knows this core (core ID 8, `fpga_firmware-bl616`
with `core/burgertime.cpp`). ROMs are not included. You need your own MAME ROM set, named as
in the MRA's `<rom zip=...>`. The main menu's "Arcade" entry lists `arcade/`; choose the
`.mra`. As on MiSTer, the firmware reads the MRA (`<rbf>burgertime</rbf>` selects this core),
builds the ROM image from the zip (the ROM files in the order the MRA gives, with its padding),
and sends it to the core together with the MRA's DIP switch defaults. The MRA's
`<rom index="3">` (MiSTer's high score table) and `<nvram>` are not used.

## ROM loading

The core is TangCore core ID 8. `iosys_bl616` receives the firmware's commands over the UART
(2 Mbaud) and hands the ROM image to `rom_stream.sv` byte by byte, from image offset 0, between
`rom_loading` going 0 -> 1 and 1 -> 0. The whole image is kept in block RAM. Image layout
(offset):

| Offset | Size | Contents | Core memory |
|---|---|---|---|
| 0x0000 | 4 KB | Sound CPU program `ab14.12h` (CPU 0xE000-0xEFFF) | sound program ROM |
| 0x1000 | 12 KB | Padding, 0xFF | not stored: the main CPU reads 0xFF at 0x9000-0xBFFF |
| 0x4000 | 16 KB | Main CPU program `aa04`, `aa06`, `aa05`, `aa07` (CPU 0xC000-0xFFFF) | program ROM |
| 0x8000 | 24 KB | Foreground and sprite graphics, 3 planes of 8 KB | `fg_sp_graphx_1..3` |
| 0xE000 | 6 KB | Background graphics, 3 planes of 2 KB | `bg_graphx_1..3` |
| 0xF800 | 2 KB | Background tile map | `bg_map` |

The image is 0x10000 bytes (65536), about 0.35 s at 2 Mbaud. Bytes from 0x10000 on are
ignored. The core is held in reset from power-up until a load has ended with at least 0x10000
bytes, and again during every new load. `rom_stream.sv` hands each byte from the 32 MHz iosys
clock to the core's 48 MHz download port with a request/acknowledge handshake.

The firmware also sends a 32-bit core configuration (iosys `core_config`) when the game loads,
and again whenever the menu's "Rotate screen" changes:

| Bits | Meaning |
|---|---|
| 7-0 | MRA switch byte 0. The core gets `dip_sw1 = byte ^ 0x3F`, as on MiSTer |
| 15-8 | MRA switch byte 1. The core gets `dip_sw2 = ~byte`, as on MiSTer |
| 16 | 1 = rotate the picture (the menu's "Rotate screen") |
| 31-17 | 0 |

The MRA default is `00,14`: 1 coin 1 credit, upright cabinet, 3 chefs, a bonus chef every
20000 points. The meaning of each bit is in the `<switches>` block of the MRA.

## Controls

Gamepads: USB gamepads through the BL616 firmware, and SNES and DualShock pads on the pins
TangCore's nestang uses. Pad 1 and pad 2 both drive the same controls, and those go to both
players' inputs, as on MiSTer (the two players take turns).

| Pad | Game |
|---|---|
| D-pad | Joystick (passed as is; the game uses 4 ways) |
| B, Y or A | Pepper |
| SELECT | Coin |
| START on pad 1 | 1P start |
| START on pad 2, or R on either pad | 2P start |
| Board button S1 | Coin and 1P start together (debounced, about 11 ms) |

The firmware opens its menu with the key combination chosen in its options. While the menu is
shown the game is paused (sound too) and gets no buttons; the screen keeps the last picture.
The in-game menu has "Rotate screen: On / Off" (default On), saved in `tangcore.ini` as
`rotate=on|off` in the `[burgertime]` section. The volume (firmware options) sets the HDMI
audio level.

## LEDs

Both LEDs are active low (on when the pin is driven low).

| LED | On means |
|---|---|
| LED0 (pin 15) | A ROM is loaded and the core is running |
| LED1 (pin 16) | A ROM is loading, or the last load ended with fewer than 0x10000 bytes (the core stays in reset) |

## How it works

**Clocks.** The game PLL makes 48 MHz and 32 MHz from the 27 MHz crystal, the HDMI PLL
371.25 MHz, divided by 5 to the 74.25 MHz pixel clock. The whole core runs on 48 MHz with clock
enables that stand for the original clocks: `ce12` (one 48 MHz cycle in four) for the 12 MHz
clock's rising edge, `ce12n` for its falling edge (the memories' read clock), and enables for
the 6 MHz pixel clock, the 1.5 MHz main CPU, the 500 kHz sound CPU and the 1.5 MHz AY-3-8910s.
The game's timing is the original: 6 MHz pixel clock, 384 x 272 pixels per frame, 57.44 Hz.
The SDRAM, iosys, ROM loading and gamepads run on 32 MHz.

**Frame buffer.** The game runs at 57.44 Hz and HDMI at 60 Hz, so the picture goes through
three frame buffers in the embedded SDRAM. `fb_writer.sv` takes the core's pixels (RGB 3:3:2,
one byte each, four to a 32-bit SDRAM word): the 240 x 240 area MAME shows (the core's active
picture is 253 x 240; the frame buffer keeps its columns 6-245). It stages 4 lines at a time
in block RAM and writes them into a free buffer in the order they will be shown, rotated or
not, so the reader always reads display rows straight through. A finished frame becomes the
latest; at the start of each HDMI frame `fb_reader.sv` takes the latest finished buffer and
shows it whole, so a frame is never torn. Some game frames are shown twice (about one in 23).

**Rotation.** The original monitor is mounted on its side. With "Rotate screen" on, the picture
is turned clockwise, as the MRA says (`vertical (cw)`); when the game flips the screen for
player 2 of a cocktail cabinet, it is turned counter-clockwise instead, as the MiSTer core
does. Each buffer records whether it was written rotated, so a change of the option takes
effect on the next whole frame.

**Layout on the 1280 x 720 screen,** centred, black around it:

| Rotate | Scale | Picture |
|---|---|---|
| On | 3x across, 3x down | 720 x 720 |
| Off | 4x across, 3x down | 960 x 720, the original 4:3 shape |

**Menu.** The firmware's menu (iosys `textdisp`, 256 x 224 pixels) is drawn 3x across and 3x
down in a 768 x 672 window in the middle of the screen, the same window as the monitor core's
main menu and the NES and SNES cores, over the picture dimmed to a quarter. The volume bar is a
strip of it over the running game.

**Audio.** The core's 11-bit unsigned audio (updated at 23.4 kHz) is used as MiSTer does
(`{audio, 5'b0}`), made signed by inverting the top bit, and sent on both HDMI channels at
48 kHz, 16 bit: each HDMI sample takes the core's latest sample, so the pitch is unchanged.
`hdmi.sv` scales it by the firmware's master volume.

**SDRAM.** One access at a time, CAS latency 2, auto precharge, at 32 MHz. The frame buffer
uses 32-bit word accesses; the writer and the reader take turns, and the SDRAM is busy about
28% of the time.

## Known limitations

- No high score saving (the MiSTer core's `hiscore.v` is not ported).
- Rotated, the picture is 720 x 720 (3x across): the original 3:4 tube shape would be 540
  wide, which needs a scale of 2.25.
- The frame buffer shows MAME's 240 x 240 visible area; the core's active picture is 253
  pixels wide, and the columns outside MAME's area, always blank in the simulations, are not
  shown.
- Not ported from the MiSTer core: the "Flip Screen" option, the 59.8 Hz video timing option,
  the 0.75 MHz CPU option and MiSTer's pause and dim options. The second coin input is not
  used (SELECT is coin 1).
