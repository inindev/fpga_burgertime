// top.sv - BurgerTime on the Sipeed Tang Nano 20K (GW2AR-LV18QN88C8/I7), TangCore core
//
//   27 MHz crystal (pin 4)
//     |-- gowin_pll_game : 96 MHz VCO tap -> CLKOUTD 48 MHz (clkm_48MHZ), CLKOUTD3 32 MHz (clkm_32MHZ)
//     '-- gowin_pll_hdmi : 371.25 MHz -> CLKDIV/5 -> 74.25 MHz pixel clock
//
//   BL616 (UART) <-> iosys_bl616 (32 MHz): menu overlay, ROM stream, gamepads, DIP switches,
//                    rotate option, volume
//   iosys rom_do --> rom_stream --> dn_addr/dn_data/dn_wr (48 MHz) -> core block RAM (64 KB)
//   core (burger_time.vhd, 48 MHz) video --> framebuffer (SDRAM, rotation, + menu overlay)
//                                       --> hdmi (720p60, audio)
//
// The core is held in reset from power-up until a ROM image has been loaded, and again for
// every new load. The core runs on 48 MHz with its own clock enables (6 MHz pixel clock,
// 384 x 272, 57.44 Hz, as the original board); the frame buffer (framebuffer.sv) decouples
// it from the 60 Hz HDMI output and rotates the picture when core_config[16] is set.
//
// Gamepads (SNES layout, 1 = pressed: R L X A RT LT DN UP START SELECT Y B, bits 11..0): USB
// gamepads on the BL616 (iosys hid1/hid2), SNES pads (pins 25-30) and DualShock pads (pins 17-20,
// 52, 53, 71, 72), as in nestang's Nano 20K build. Both pads drive the same controls, and
// those drive both players' inputs (the game alternates players), as the MiSTer core does:
//   D-pad: joystick    B, Y or A: pepper (fire)    SELECT: coin 1
//   START: 1P start on pad 1, 2P start on pad 2   R: 2P start (either pad)
//   board button S1: coin 1 and 1P start together
// While the menu is shown (not the volume strip) the game is paused (the core's pause input,
// which stops all its clock enables) and gets no buttons.
//
// Other boards: this file is the top level for every board. A board file read before it
// (tang/console/, tang/primer25k/) sets the differences: GW5A (Tang Console 60K/138K, Primer
// 25K: 50 MHz clock, their PLLs, front USB host, no onboard amp or RGB LED), S1_ACTIVE_LOW,
// SDRAM16 (the 16-bit Tang SDRAM module, tang/gw5a/sdram16.v), USB2 (a second USB port) and
// the pads (CONTROLLER_SNES or CONTROLLER_DS2, as they share one PMOD). Without a board file it
// is the Tang Nano 20K, with both pad types.

`ifndef GW5A
`define CONTROLLER_SNES
`define CONTROLLER_DS2
`endif

module top (
    input  logic        sys_clk,                // 27 MHz, pin 4 (GW5A boards: 50 MHz)
    input  logic        s1,                     // board button S1, active high (pin 88) (Console: active low)
    output logic [1:0]  led,                    // active low

    // UART to the BL616
    input  logic        UART_RXD,
    output logic        UART_TXD,

`ifdef CONTROLLER_SNES
    // SNES controllers
    output logic        joy1_strb,
    output logic        joy1_clk,
    input  logic        joy1_data,
    output logic        joy2_strb,
    output logic        joy2_clk,
    input  logic        joy2_data,
`endif

`ifdef CONTROLLER_DS2
    // DualShock controllers
    output logic        ds_clk,
    input  logic        ds_miso,
    output logic        ds_mosi,
    output logic        ds_cs,
    output logic        ds_clk2,
    input  logic        ds_miso2,
    output logic        ds_mosi2,
    output logic        ds_cs2,
`endif

`ifdef GW5A
    // front USB-A ports: USB host on the FPGA (usb_hid_host.v)
    inout  wire         usb1_dp,
    inout  wire         usb1_dn,
`ifdef USB2
    inout  wire         usb2_dp,
    inout  wire         usb2_dn,
`endif
`endif

`ifndef GW5A
    // onboard parts
    output logic        pa_en,                  // audio amp enable: held off
    output logic        ws2812,                 // RGB LED: sent "off" once at power-up
`endif

`ifdef SDRAM16
    // Tang SDRAM module (16-bit); the header has no CKE pin
    output logic        O_sdram_clk,
    output logic        O_sdram_cs_n,
    output logic        O_sdram_cas_n,
    output logic        O_sdram_ras_n,
    output logic        O_sdram_wen_n,
    inout  wire  [15:0] IO_sdram_dq,
    output logic [12:0] O_sdram_addr,
    output logic [1:0]  O_sdram_ba,
    output logic [1:0]  O_sdram_dqm,
`else
    // embedded SDRAM (no pin constraints: placed by the tool)
    output logic        O_sdram_clk,
    output logic        O_sdram_cke,
    output logic        O_sdram_cs_n,
    output logic        O_sdram_cas_n,
    output logic        O_sdram_ras_n,
    output logic        O_sdram_wen_n,
    inout  wire  [31:0] IO_sdram_dq,
    output logic [10:0] O_sdram_addr,
    output logic [1:0]  O_sdram_ba,
    output logic [3:0]  O_sdram_dqm,
`endif

    // HDMI
    output logic        tmds_clk_n,
    output logic        tmds_clk_p,
    output logic [2:0]  tmds_d_n,
    output logic [2:0]  tmds_d_p
);

    localparam integer CLK32_HZ = 32_000_000;   // iosys, controllers, SDRAM

    // ------------------------------------------------------------------ clocks
    logic clkm_48MHZ, clkm_32MHZ;
    logic hclk5, hclk;
    logic sys_resetn = 1'b0;            // see "resets" below

`ifdef GW5A
    // 50 MHz -> 27 MHz, as fpga_nestang's Console build; from it the game PLL (48 and 32 MHz)
    // and the HDMI PLL
    logic clk27;
    gowin_pll_27 u_pll_27 (
        .clkin  (sys_clk),
        .clkout0(clk27)
    );

    gowin_pll_game u_pll_game (
        .clkin  (clk27),
        .clkout0(clkm_48MHZ),
        .clkout1(clkm_32MHZ)
    );

    gowin_pll_hdmi u_pll_hdmi (
        .clkin (clk27),
        .clkout(hclk5)
    );
`else
    gowin_pll_game u_pll_game (
        .clkin   (sys_clk),
        .clkout  (),                    // 96 MHz, not used
        .clkoutd (clkm_48MHZ),
        .clkoutd3(clkm_32MHZ),
        .lock    ()
    );

    gowin_pll_hdmi u_pll_hdmi (
        .clkin (sys_clk),
        .clkout(hclk5),
        .lock  ()
    );
`endif

    CLKDIV #(.DIV_MODE(5)) u_div5 (
        .CLKOUT(hclk),
        .HCLKIN(hclk5),
        .RESETN(sys_resetn),
        .CALIB (1'b0)
    );

`ifdef GW5A
    // SDRAM clocks as fpga_nestang / fpga_snestang on the Tang Console: the controller on
    // 64.5 MHz (clk_sd), the SDRAM clock pin a second output of the same PLL, 225 degrees later.
    // sd_resetn is the system reset in clk_sd's domain (first flop *_meta, see the .sdc).
    logic clk_sd;
    gowin_pll_sdram u_pll_sdram (
        .clkin  (sys_clk),
        .clkout0(),
        .clkout1(clk_sd),
        .clkout2(O_sdram_clk)
    );
    logic sd_rst_meta = 1'b0, sd_resetn = 1'b0;
    always_ff @(posedge clk_sd) {sd_resetn, sd_rst_meta} <= {sd_rst_meta, sys_resetn};
`else
    // SDRAM clock = ~clkm_32MHZ, made by an ODDR in the I/O block (low after the rising
    // edge, high after the falling edge) so its delay does not depend on placement.
    ODDR u_sdram_clk (
        .Q0 (O_sdram_clk),
        .Q1 (),
        .D0 (1'b0),
        .D1 (1'b1),
        .TX (1'b0),
        .CLK(clkm_32MHZ)
    );
`endif

`ifndef GW5A
    // ------------------------------------------------------------------ onboard parts
    // Keep the onboard audio amp off (MAX98357A SD_MODE, low = shutdown)
    assign pa_en = 1'b0;

    // Turn the onboard WS2812 RGB LED off: it can latch a colour from noise while the FPGA
    // configures. At 27 MHz (sys_clk): hold low 8192 cycles (303 us, a reset), send 24 zero bits
    // (34 cycles = 1.26 us each, high for 8 = 296 ns), then stay low. From nestang_top.sv.
    logic [12:0] ws_rst = 13'd0;
    logic [5:0]  ws_ph  = 6'd0;
    logic [4:0]  ws_bit = 5'd0;
    logic        ws_done = 1'b0;
    logic        ws_out  = 1'b0;
    always_ff @(posedge sys_clk) begin
        ws_out <= 1'b0;
        if (!ws_done) begin
            if (ws_rst != 13'h1fff)
                ws_rst <= ws_rst + 13'd1;
            else begin
                ws_out <= ws_ph < 6'd8;
                if (ws_ph != 6'd33)
                    ws_ph <= ws_ph + 6'd1;
                else begin
                    ws_ph <= 6'd0;
                    if (ws_bit == 5'd23)
                        ws_done <= 1'b1;
                    else
                        ws_bit <= ws_bit + 5'd1;
                end
            end
        end
    end
    assign ws2812 = ws_out;
`endif

    // ------------------------------------------------------------------ resets
    // One system reset, released once 65535 clocks (about 2 ms) after power-up and never asserted
    // again, as in the monitor core and snestang. The PLL lock outputs are not used.
    logic [15:0] resetcnt = 16'hffff;
    always_ff @(posedge clkm_32MHZ) begin
        resetcnt <= resetcnt == 0 ? 16'd0 : resetcnt - 16'd1;
        if (resetcnt == 0)
            sys_resetn <= 1'b1;
    end

`ifdef GW5A
    // ------------------------------------------------------------------ front USB-A ports
    // USB host on the FPGA for gamepads on the Console's front USB-A ports, as in the other
    // Console cores (usb_hid_host.v, 12 MHz from its own PLL). Their buttons go to the pads and
    // the menu like the board's own pads.
    logic        clk12, pll_lock_12;
    logic [11:0] joy_usb1_12, joy_usb2_12, joy_usb1, joy_usb2;
    pll_12 u_pll_12 (.clkin(sys_clk), .clkout0(clk12), .lock(pll_lock_12));
    usb_hid_host u_usb1 (
        .usbclk(clk12), .usbrst_n(pll_lock_12),
        .usb_dm(usb1_dn), .usb_dp(usb1_dp), .game_snes(joy_usb1_12)
    );
    usb_hid_sync u_usb1_sync (.clk(clkm_32MHZ), .d(joy_usb1_12), .q(joy_usb1));
`ifdef USB2
    usb_hid_host u_usb2 (
        .usbclk(clk12), .usbrst_n(pll_lock_12),
        .usb_dm(usb2_dn), .usb_dp(usb2_dp), .game_snes(joy_usb2_12)
    );
    usb_hid_sync u_usb2_sync (.clk(clkm_32MHZ), .d(joy_usb2_12), .q(joy_usb2));
`else
    assign joy_usb2 = '0;
`endif
`endif

    // ------------------------------------------------------------------ iosys (BL616 link)
    logic        overlay, osd_strip;
    logic [7:0]  overlay_x, overlay_y;
    logic [14:0] overlay_color;
    logic [15:0] hid1, hid2;
    logic [11:0] joy1_snes, joy2_snes, joy1_ds2, joy2_ds2;
    logic [7:0]  rom_loading;
    logic [7:0]  rom_do;
    logic        rom_do_valid;
    logic [31:0] core_config;
    logic [3:0]  volume;

    iosys_bl616 #(
        .FREQ      (CLK32_HZ),
        .CORE_ID   (8),
        .COLOR_LOGO(15'b00000_10011_11111)      // BGR5, orange
    ) u_iosys (
        .clk           (clkm_32MHZ),
        .hclk          (hclk),
        .resetn        (sys_resetn),
        .overlay       (overlay),
        .osd_strip     (osd_strip),
        .overlay_x     (overlay_x),
        .overlay_y     (overlay_y),
        .overlay_color (overlay_color),
`ifdef GW5A
        .joy1          (joy1_snes | joy1_ds2 | joy_usb1),   // the board's own pads and front
        .joy2          (joy2_snes | joy2_ds2 | joy_usb2),   // USB ports, for the menu
`else
        .joy1          (joy1_snes | joy1_ds2),  // the board's own pads, for the menu
        .joy2          (joy2_snes | joy2_ds2),
`endif
        .hid1          (hid1),
        .hid2          (hid2),
        .rom_loading   (rom_loading),
        .rom_do        (rom_do),
        .rom_do_valid  (rom_do_valid),
        .mgmt_address  (),
        .mgmt_read     (),
        .mgmt_readdata (16'h0000),
        .mgmt_write    (),
        .mgmt_writedata(),
        .fdd_request   (2'b00),
        .kbd_data      (),
        .kbd_data_valid(),
        .core_config   (core_config),
        .volume        (volume),
        .uart_rx       (UART_RXD),
        .uart_tx       (UART_TXD)
    );

    // menu shown: game paused, no buttons (a register, as it goes into a synchroniser)
    logic menu_32 = 1'b0;
    always_ff @(posedge clkm_32MHZ) menu_32 <= overlay & ~osd_strip;

    // Core configuration from the firmware (iosys command 0x03), sent when a game loads and
    // again when the menu's Rotate screen changes. core_config is a clkm_32MHZ register; one
    // more register here so its uses do not load it.
    //   [7:0] MRA switch byte 0, [15:8] MRA switch byte 1, [16] rotate the picture
    logic [31:0] cfg = 32'h0;
    always_ff @(posedge clkm_32MHZ) cfg <= core_config;

    // ------------------------------------------------------------------ gamepads
`ifdef CONTROLLER_SNES
    controller_snes #(.FREQ(CLK32_HZ)) u_joy1_snes (
        .clk(clkm_32MHZ), .resetn(sys_resetn), .buttons(joy1_snes),
        .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data)
    );
    controller_snes #(.FREQ(CLK32_HZ)) u_joy2_snes (
        .clk(clkm_32MHZ), .resetn(sys_resetn), .buttons(joy2_snes),
        .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data)
    );
`else
    assign joy1_snes = '0;
    assign joy2_snes = '0;
`endif
`ifdef CONTROLLER_DS2
    controller_ds2 #(.FREQ(CLK32_HZ)) u_joy1_ds2 (
        .clk(clkm_32MHZ), .snes_buttons(joy1_ds2),
        .ds_clk(ds_clk), .ds_miso(ds_miso), .ds_mosi(ds_mosi), .ds_cs(ds_cs)
    );
    controller_ds2 #(.FREQ(CLK32_HZ)) u_joy2_ds2 (
        .clk(clkm_32MHZ), .snes_buttons(joy2_ds2),
        .ds_clk(ds_clk2), .ds_miso(ds_miso2), .ds_mosi(ds_mosi2), .ds_cs(ds_cs2)
    );
`else
    assign joy1_ds2 = '0;
    assign joy2_ds2 = '0;
`endif

    // All sources of each pad, SNES layout, 1 = pressed
`ifdef GW5A
    wire [11:0] pad1 = joy1_snes | joy1_ds2 | hid1[11:0] | joy_usb1;
    wire [11:0] pad2 = joy2_snes | joy2_ds2 | hid2[11:0] | joy_usb2;
`else
    wire [11:0] pad1 = joy1_snes | joy1_ds2 | hid1[11:0];
    wire [11:0] pad2 = joy2_snes | joy2_ds2 | hid2[11:0];
`endif
    wire [11:0] pads = pad1 | pad2;

    // Controls, 1 = pressed
    logic [7:0] ctl_32 = '0;
    always_ff @(posedge clkm_32MHZ) begin
        ctl_32[0] <= pads[7];                   // right
        ctl_32[1] <= pads[6];                   // left
        ctl_32[2] <= pads[5];                   // down
        ctl_32[3] <= pads[4];                   // up
        ctl_32[4] <= pads[0] | pads[1] | pads[8]; // pepper (fire): B, Y, A
        ctl_32[5] <= pads[2];                   // coin 1: SELECT
        ctl_32[6] <= pad1[3];                   // 1P start: START on pad 1
        ctl_32[7] <= pad2[3] | pads[11];        // 2P start: START on pad 2, R
        if (menu_32) ctl_32 <= '0;
    end

    // ------------------------------------------------------------------ ROM loading
    logic        loaded, short_load;
    logic [16:0] dn_addr;
    logic [7:0]  dn_data;
    logic        dn_wr;
    wire         loading = rom_loading != 8'd0;

    rom_stream u_stream (
        .clk         (clkm_32MHZ),
        .resetn      (sys_resetn),
        .loading     (loading),
        .rom_do      (rom_do),
        .rom_do_valid(rom_do_valid),
        .loaded      (loaded),
        .short_load  (short_load),
        .clk_core    (clkm_48MHZ),
        .dn_addr     (dn_addr),
        .dn_data     (dn_data),
        .dn_wr       (dn_wr)
    );

    // core reset: released 16 clocks after a complete load, asserted again as soon as the next
    // load starts (loading is checked directly so the core stops before the first byte)
    logic [4:0] core_rst_cnt = '0;
    logic       core_rst_n   = 1'b0;
    always_ff @(posedge clkm_32MHZ) begin
        if (!sys_resetn || !loaded || loading) begin
            core_rst_cnt <= '0;
            core_rst_n   <= 1'b0;
        end else if (!core_rst_cnt[4]) begin
            core_rst_cnt <= core_rst_cnt + 1'b1;
        end else
            core_rst_n <= 1'b1;
    end

    // ------------------------------------------------------------------ inputs (48 MHz)
    // Into the core's 48 MHz clock, two flops each (the first *_meta; see burgertime.sdc):
    // the core reset, the menu state (pause), the controls and the DIP switches. The DIP
    // switches are one 16-bit value: a new value is taken only when two consecutive reads
    // agree, so all bits come from the same core_config. The rotate bit goes to the frame
    // buffer, which synchronises it itself.
    logic       rst_meta = 1'b0, rst_s = 1'b0;
    logic       pause_meta = 1'b0, pause_48 = 1'b0;
    logic [7:0] ctl_meta = '0, ctl_48 = '0;
    logic [15:0] dip_meta = '0, dip_s = '0, dip_s2 = '0, dip_48 = '0;
    always_ff @(posedge clkm_48MHZ) begin
        {rst_s, rst_meta}      <= {rst_meta, core_rst_n};
        {pause_48, pause_meta} <= {pause_meta, menu_32};
        {ctl_48, ctl_meta}     <= {ctl_meta, ctl_32};
        {dip_s2, dip_s, dip_meta} <= {dip_s, dip_meta, cfg[15:0]};
        if (dip_s == dip_s2) dip_48 <= dip_s;
    end

    // S1 is active high (Console: active low, inverted here).
    logic [1:0] s1_sr = 2'b00;
`ifdef S1_ACTIVE_LOW
    always_ff @(posedge clkm_48MHZ) s1_sr <= {s1_sr[0], ~s1};
`else
    always_ff @(posedge clkm_48MHZ) s1_sr <= {s1_sr[0], s1};
`endif

    // Debounce: s1_db takes the synchronised level only after it has differed from s1_db for
    // 2^S1_DB_BITS consecutive clocks; any bounce back restarts the count.
    //   S1_DB_BITS = $clog2(48 MHz * 10 ms) = $clog2(480000) = 19
    //   -> 2^19 / 48 MHz = 10.9 ms stable time (and press/release latency).
    localparam integer CORE_HZ    = 48_000_000;
    localparam integer S1_DB_BITS = $clog2(CORE_HZ / 100);
    logic [S1_DB_BITS-1:0] s1_cnt = '0;
    logic                  s1_db  = 1'b0;
    always_ff @(posedge clkm_48MHZ) begin
        if (s1_sr[1] == s1_db)
            s1_cnt <= '0;
        else if (&s1_cnt) begin
            s1_db  <= s1_sr[1];
            s1_cnt <= '0;
        end else
            s1_cnt <= s1_cnt + 1'b1;
    end

    // Core inputs, 1 = pressed. Both players get the same joystick and pepper button.
    logic [7:0] btn = '0;
    logic       core_reset = 1'b1;
    always_ff @(posedge clkm_48MHZ) begin
        btn        <= {ctl_48[7], ctl_48[6] | s1_db, ctl_48[5] | s1_db, ctl_48[4:0]};
        core_reset <= ~rst_s;
    end

    // ------------------------------------------------------------------ core
    logic        video_ce, hs, vs, hblank, vblank, csync, flipped;
    logic [2:0]  red, green;
    logic [1:0]  blue;
    logic [10:0] audio;

    burger_time u_core (
        .clock_48        (clkm_48MHZ),
        .reset           (core_reset),
        .pause           (pause_48),
        .dn_addr         (dn_addr),
        .dn_data         (dn_data),
        .dn_wr           (dn_wr),
        .video_ce        (video_ce),
        .video_r         (red),
        .video_g         (green),
        .video_b         (blue),
        .video_hs        (hs),
        .video_vs        (vs),
        .video_vblank    (vblank),
        .video_hblank    (hblank),
        .video_csync     (csync),
        .audio_out       (audio),
        .start1          (btn[6]),
        .start2          (btn[7]),
        .coin1           (btn[5]),
        .coin2           (1'b0),
        .fire1           (btn[4]),
        .right1          (btn[0]),
        .left1           (btn[1]),
        .down1           (btn[2]),
        .up1             (btn[3]),
        .fire2           (btn[4]),
        .right2          (btn[0]),
        .left2           (btn[1]),
        .down2           (btn[2]),
        .up2             (btn[3]),
        .dip_sw1         (dip_48[7:0] ^ 8'h3f),     // as MiSTer: MRA switch byte 0 xor 0x3F
        .dip_sw2         (~dip_48[15:8]),           // as MiSTer: not MRA switch byte 1
        .screen_flipped_o(flipped)
    );

    // ------------------------------------------------------------------ video
    // Frame buffer in SDRAM: the core's pixels (240 x 240 from active pixel 6, see
    // framebuffer.sv) into one of three buffers, rotated or not; the HDMI side shows the
    // latest finished one, scaled and centred on 1280 x 720, with the menu overlay.
    logic [10:0] cx, frame_width;
    logic [9:0]  cy, frame_height;
    logic [23:0] rgb;
    logic [2:0]  tmds;

    framebuffer u_fb (
        .clk_core      (clkm_48MHZ),
        .pix_en        (video_ce),
        .pix           ({red, green, blue}),
        .hblank        (hblank),
        .vblank        (vblank),
        .screen_flipped(flipped),
        .rotate        (cfg[16]),
`ifdef GW5A
        .clk_sd        (clk_sd),
        .resetn        (sd_resetn),
`else
        .clk_sd        (clkm_32MHZ),
        .resetn        (sys_resetn),
`endif
        .clk_pix       (hclk),
        .cx            (cx),
        .cy            (cy),
        .frame_width   (frame_width),
        .frame_height  (frame_height),
        .rgb           (rgb),
        .overlay       (overlay),
        .osd_strip     (osd_strip),
        .overlay_x     (overlay_x),
        .overlay_y     (overlay_y),
        .overlay_color (overlay_color),
        .overrun       (),
        .sdram_dq      (IO_sdram_dq),
        .sdram_a       (O_sdram_addr),
        .sdram_ba      (O_sdram_ba),
        .sdram_dqm     (O_sdram_dqm),
        .sdram_cs_n    (O_sdram_cs_n),
        .sdram_ras_n   (O_sdram_ras_n),
        .sdram_cas_n   (O_sdram_cas_n),
        .sdram_we_n    (O_sdram_wen_n)
`ifndef SDRAM16
        ,
        .sdram_cke     (O_sdram_cke)
`endif
    );

    // ------------------------------------------------------------------ audio
    // 48 kHz timing from 74.25 MHz: toggle clk_audio at 96 kHz with a fractional accumulator
    // (96000 / 74250000 per clock), so clk_audio rises at exactly 48 kHz on average.
    // audio_en_48k is a 1-clock enable on each rising edge of clk_audio; audio_sample_word
    // is updated there.
    // The core's audio (11 bit unsigned, a 48 MHz register updated at 23.4 kHz) is brought over
    // with a 2-flop synchroniser plus a "two reads agree" filter so all bits come from one
    // sample. Each HDMI sample takes the latest core sample (sample and hold, the pitch is
    // unchanged). As MiSTer (AUDIO_L = {audio, 5'b0}, unsigned), made signed by inverting the
    // top bit, the same on both channels.
    localparam integer HCLK_HZ = 74_250_000;
    logic [31:0] aud_acc = '0;
    wire  [31:0] aud_acc_n = aud_acc + 32'd96000;
    logic        clk_audio = 1'b0, audio_en_48k = 1'b0;

    always_ff @(posedge hclk) begin
        audio_en_48k <= 1'b0;
        if (aud_acc_n >= HCLK_HZ) begin
            aud_acc   <= aud_acc_n - HCLK_HZ;
            clk_audio <= ~clk_audio;
            if (!clk_audio) audio_en_48k <= 1'b1;
        end else
            aud_acc <= aud_acc_n;
    end

    // syn_srlstyle: without it Gowin builds aud_meta -> aud_s1 -> aud_s2 as a shift register in
    // LUT RAM (RAM16), which is no synchroniser.
    logic [10:0] aud_meta /* synthesis syn_srlstyle = "registers" */;
    logic [10:0] aud_s1   /* synthesis syn_srlstyle = "registers" */;
    logic [10:0] aud_s2   /* synthesis syn_srlstyle = "registers" */;
    logic [10:0] aud_ok = '0;
    always_ff @(posedge hclk) begin
        aud_meta <= audio; aud_s1 <= aud_meta; aud_s2 <= aud_s1;
        if (aud_s1 == aud_s2) aud_ok <= aud_s1;
    end

    wire [15:0] audio_s16 = {~aud_ok[10], aud_ok[9:0], 5'b0};

    logic [15:0] audio_sample_word [1:0];
    always_ff @(posedge hclk) begin
        if (audio_en_48k) begin
            audio_sample_word[0] <= audio_s16;
            audio_sample_word[1] <= audio_s16;
        end
    end

    // ------------------------------------------------------------------ HDMI
    hdmi #(
        .VIDEO_ID_CODE     (4),
        .DVI_OUTPUT        (0),
        .VIDEO_REFRESH_RATE(60.0),
        .IT_CONTENT        (1),
        .AUDIO_RATE        (48000),
        .AUDIO_BIT_WIDTH   (16),
        .START_X           (0),
        .START_Y           (0)
    ) u_hdmi (
        .clk_pixel_x5      (hclk5),
        .clk_pixel         (hclk),
        .clk_audio         (clk_audio),
        .reset             (1'b0),
        .rgb               (rgb),
        .audio_sample_word (audio_sample_word),
        .volume            (volume),        // iosys master volume, synchronised in hdmi.sv
        .tmds              (tmds),
        .tmds_clock        (),
        .cx                (cx),
        .cy                (cy),
        .frame_width       (frame_width),
        .frame_height      (frame_height),
        .screen_width      (),
        .screen_height     ()
    );

    ELVDS_OBUF tmds_bufds [3:0] (
        .I ({hclk, tmds}),
        .O ({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

    // ------------------------------------------------------------------ LEDs (active low)
    //   led[0] on = a ROM is loaded and the core runs
    //   led[1] on = a ROM is loading, or the last load ended short (core held in reset)
    assign led[0] = ~core_rst_n;
    assign led[1] = ~(loading | short_load);

endmodule
