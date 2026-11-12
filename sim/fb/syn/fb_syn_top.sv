// fb_syn_top.sv - Gowin build check of the frame buffer alone (not a usable core): the real
// PLLs and clocks, framebuffer.sv on the embedded SDRAM, a stand-in for the core's video (the
// BurgerTime timing with pseudo-random pixels) and the hdl-util 720p counters. The picture is
// folded into one LED so nothing is optimised away. Used to see block RAM inference, logic use
// and timing of the frame buffer with the clocks it will run on. See syn.tcl.

module fb_syn_top (
    input  logic        sys_clk,
    input  logic        s1,
    output logic [1:0]  led,

    output logic        O_sdram_clk,
    output logic        O_sdram_cke,
    output logic        O_sdram_cs_n,
    output logic        O_sdram_cas_n,
    output logic        O_sdram_ras_n,
    output logic        O_sdram_wen_n,
    inout  wire  [31:0] IO_sdram_dq,
    output logic [10:0] O_sdram_addr,
    output logic [1:0]  O_sdram_ba,
    output logic [3:0]  O_sdram_dqm
);

    logic clkm_48MHZ, clkm_32MHZ, hclk5, hclk;
    logic sys_resetn = 1'b0;

    gowin_pll_game u_pll_game (
        .clkin(sys_clk), .clkout(), .clkoutd(clkm_48MHZ), .clkoutd3(clkm_32MHZ), .lock()
    );
    gowin_pll_hdmi u_pll_hdmi (.clkin(sys_clk), .clkout(hclk5), .lock());
    CLKDIV #(.DIV_MODE(5)) u_div5 (.CLKOUT(hclk), .HCLKIN(hclk5), .RESETN(sys_resetn), .CALIB(1'b0));

    ODDR u_sdram_clk (.Q0(O_sdram_clk), .Q1(), .D0(1'b0), .D1(1'b1), .TX(1'b0), .CLK(clkm_32MHZ));

    logic [15:0] resetcnt = 16'hffff;
    always_ff @(posedge clkm_32MHZ) begin
        resetcnt <= resetcnt == 0 ? 16'd0 : resetcnt - 16'd1;
        if (resetcnt == 0) sys_resetn <= 1'b1;
    end

    // stand-in for the core's video: 6 MHz pixel enable, 384 x 272, blanks as burger_time.vhd
    logic [2:0]  div = 3'd0;
    logic        pix_en = 1'b0;
    logic [8:0]  hcnt = 9'd0, vcnt = 9'd0;
    logic        hb = 1'b1, vb = 1'b1, vhb = 1'b1, vvb = 1'b1;
    logic [15:0] lfsr = 16'hACE1;
    logic [7:0]  pix = 8'd0;
    always_ff @(posedge clkm_48MHZ) begin
        div    <= div + 1'b1;
        pix_en <= div == 3'd6;
        if (pix_en) begin
            if (hcnt == 9'd383) begin
                hcnt <= 9'd0;
                vcnt <= (vcnt == 9'd271) ? 9'd0 : vcnt + 1'b1;
            end else
                hcnt <= hcnt + 1'b1;
            if (hcnt == 9'd267) hb <= 1'b1; else if (hcnt == 9'd14) hb <= 1'b0;
            if (vcnt == 9'd248) vb <= 1'b1; else if (vcnt == 9'd8) vb <= 1'b0;
            vhb  <= hb;
            vvb  <= vb;
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            pix  <= lfsr[7:0];
        end
    end

    // 720p counters as hdl-util hdmi makes them
    logic [10:0] cx = 11'd0;
    logic [9:0]  cy = 10'd0;
    always_ff @(posedge hclk) begin
        cx <= (cx == 11'd1649) ? 11'd0 : cx + 1'b1;
        if (cx == 11'd1649) cy <= (cy == 10'd749) ? 10'd0 : cy + 1'b1;
    end

    logic [23:0] rgb;
    logic [7:0]  ox, oy;
    logic [14:0] ocol = 15'd0, ocol_d = 15'd0;
    always_ff @(posedge hclk) begin
        ocol_d <= {ox[6:0], oy};
        ocol   <= ocol_d;
    end

    logic overrun;
    framebuffer u_fb (
        .clk_core      (clkm_48MHZ),
        .pix_en        (pix_en),
        .pix           (pix),
        .hblank        (vhb),
        .vblank        (vvb),
        .screen_flipped(lfsr[15]),
        .rotate        (s1),
        .clk_sd        (clkm_32MHZ),
        .resetn        (sys_resetn),
        .clk_pix       (hclk),
        .cx            (cx),
        .cy            (cy),
        .frame_width   (11'd1650),
        .frame_height  (10'd750),
        .rgb           (rgb),
        .overlay       (s1),
        .osd_strip     (lfsr[14]),
        .overlay_x     (ox),
        .overlay_y     (oy),
        .overlay_color (ocol),
        .overrun       (overrun),
        .sdram_dq      (IO_sdram_dq),
        .sdram_a       (O_sdram_addr),
        .sdram_ba      (O_sdram_ba),
        .sdram_dqm     (O_sdram_dqm),
        .sdram_cs_n    (O_sdram_cs_n),
        .sdram_ras_n   (O_sdram_ras_n),
        .sdram_cas_n   (O_sdram_cas_n),
        .sdram_we_n    (O_sdram_wen_n),
        .sdram_cke     (O_sdram_cke)
    );

    logic fold = 1'b0;
    always_ff @(posedge hclk) fold <= fold ^ (^rgb);
    assign led = {~overrun, fold};

endmodule
