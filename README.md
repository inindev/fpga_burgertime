# [BurgerTime](https://en.wikipedia.org/wiki/BurgerTime)

A port of the MiSTer BurgerTime core (Arcade-BurgerTime_MiSTer, by Dar, MiSTer port by Sorgelig)
to the Sipeed Tang Nano 20K, with HDMI output, as a
<a href="https://github.com/nand2mario/tangcore">TangCore</a> core: the TangCore BL616 firmware
loads it from the USB drive and sends it the game's ROMs. The picture goes through a frame
buffer in SDRAM, so it can be shown rotated (an option in the in-game menu).

<p>BurgerTime was released by Data East in 1982. The player is a chef, Peter Pepper, who walks
over the burger parts on each floor to drop them onto the plates below, while Mr. Hot Dog,
Mr. Pickle and Mr. Egg chase him. Pepper stuns them for a moment.</p>

<strong>Main CPU:</strong> 6502 at 1.5 MHz<br>
<strong>Sound CPU:</strong> 6502 at 500 kHz, with two AY-3-8910 sound chips at 1.5 MHz<br>
<strong>Video resolution:</strong> 240 x 240 visible, 6 MHz pixel clock, 57.44 Hz, vertical (rotated) monitor<br>
<strong>Video hardware:</strong> a foreground tile layer with sprites and a background tile layer (floors and ladders) from ROM, 16 colours from a palette RAM<br>

<h2>Compatible Platforms</h2>
<li>Sipeed Tang Nano 20K with the TangCore firmware (HDMI, 1280x720 at 60 Hz)</li>

<h2>Building</h2>
<p><code>gw_sh build.tcl nano20k</code> in this folder (Gowin 1.9.11.03) writes the core to <code>impl/pnr/burgertime_nano20k.bin</code>.
See <a href="tang/nano20k/BUILD.md">tang/nano20k/BUILD.md</a> for the build, where the core and the ROM zip go on the USB drive,
the controls and how the port works. <code>port_plan.md</code> is the plan the port was made to.</p>

<h2>Compatible Games</h2>
<blockquote>
<p dir="auto"><strong>ROMs NOT INCLUDED:</strong> By using this core you agree to provide your own roms.</p>
</blockquote>

<li>Burger Time (Set 1), MAME set <code>btime</code>: <code>releases/Burger Time (Set 1).mra</code>, from the MiSTer core unchanged</li>

<h2>Issues</h2>
<li>No high score saving (the MiSTer core's <code>hiscore.v</code> is not ported).</li>
<li>Rotated, the picture is 720 x 720 on the HDMI screen (each pixel 3x across, 3x down), wider than the original 3:4 tube shape, which would be 540 wide.</li>
<li>Screen flip (the MiSTer "Flip Screen" option) and the 59.8 Hz video timing option are not ported.</li>

<h2>Credits</h2>
<li>BurgerTime core: Dar (darfpga), <a href="http://darfpga.blogspot.fr">darfpga.blogspot.fr</a></li>
<li>MiSTer port: Sorgelig and the MiSTer project (<a href="https://github.com/MiSTer-devel/Arcade-BurgerTime_MiSTer">Arcade-BurgerTime_MiSTer</a>)</li>
<li>6502: T65 core by MikeJ (<code>rtl/cpu/</code>); AY-3-8910: YM2149 by MikeJ (<code>rtl/YM2149_linmix_sep.vhd</code>)</li>
<li><code>rtl/gen_ram.vhd</code>: Peter Wendrich (Syntiac)</li>
<li>TangCore IO system (<code>tang/nano20k/iosys/</code>) and the SNES/DualShock pad modules: nand2mario's TangCore and NESTang</li>
<li>HDMI encoder: hdl-util HDMI by Sameer Puri (MIT OR Apache-2.0, in <code>tang/nano20k/hdmi/</code>)</li>
<li>The board files (<code>tang/nano20k/</code>) are adapted from this project's Taito System SJ port</li>

<p>The core's source files say: "Educational use only. Do not redistribute synthetized file with
roms. Do not redistribute roms whatever the form. Use at your own risk."</p>
