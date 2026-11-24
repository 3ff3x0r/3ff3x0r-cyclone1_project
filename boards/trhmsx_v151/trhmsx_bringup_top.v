`timescale 1ps/1ps

module trhmsx_bringup_top (
    input  wire clk_21m,
    output reg vga_vs_n,
    output reg vga_hs_n,
    output reg [5:0] vga_r,
    output reg [5:0] vga_g,
    output reg [5:0] vga_b,
    input  wire cart_reset_n,
    output wire [12:0] sdram_a,
    inout  wire [15:0] sdram_dq,
    output wire [1:0] sdram_ba,
    output wire sdram_clk,
    output wire sdram_cke,
    output wire [1:0] sdram_dqm,
    output wire sdram_cs_n,
    output wire sdram_ras_n,
    output wire sdram_cas_n,
    output wire sdram_we_n,
    output wire sd_sck,
    output wire sd_mosi,
    output wire sd_cs_n,
    output wire [5:0] audio_l,
    output wire [5:0] audio_r,
    output wire joy1_strobe,
    output wire joy2_strobe,
    output wire cart_sltsl2_n,
    output wire cart_cs1_n,
    output wire cart_cs2_n,
    output wire cart_cs12_n,
    output wire cart_sltsl1_n,
    output wire cart_rfsh_n,
    output wire cart_m1_n,
    output wire cart_iorq_n,
    output wire cart_merq_n,
    output wire cart_wr_n,
    output wire cart_rd_n,
    output wire cart_clock_out,

    // Keep these pads as explicit high-impedance inputs.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire ext_clk,
    input  wire sd_dat1,
    input  wire sd_miso,
    input  wire sd_dat2,
    input  wire ps2_data,
    input  wire ps2_clk,
    input  wire ddc_sda,
    input  wire ddc_scl,
    input  wire joy1_up,
    input  wire joy1_down,
    input  wire joy1_left,
    input  wire joy1_right,
    input  wire joy1_a,
    input  wire joy1_b,
    input  wire joy2_up,
    input  wire joy2_down,
    input  wire joy2_left,
    input  wire joy2_right,
    input  wire joy2_a,
    input  wire joy2_b,
    input  wire cart_rsv5,
    input  wire cart_wait_n,
    input  wire cart_int_n,
    input  wire cart_bdir,
    input  wire cart_rsv16,
    input  wire cart_a9,
    input  wire cart_a15,
    input  wire cart_a11,
    input  wire cart_a10,
    input  wire cart_clock_return,
    input  wire cart_a7,
    input  wire cart_a6,
    input  wire cart_a12,
    input  wire cart_a8,
    input  wire cart_a14,
    input  wire cart_a13,
    input  wire cart_a1,
    input  wire cart_a0,
    input  wire cart_a3,
    input  wire cart_a2,
    input  wire cart_a5,
    input  wire cart_a4,
    input  wire cart_d1,
    input  wire cart_d0,
    input  wire cart_d3,
    input  wire cart_d2,
    input  wire cart_d5,
    input  wire cart_d4,
    input  wire cart_d7,
    input  wire cart_d6,
    input  wire cart_sw1,
    input  wire cart_sw2,
    input  wire esp_txd,
    input  wire esp_rxd,
    input  wire unused_238,
    input  wire unused_239
    /* verilator lint_on UNUSEDSIGNAL */
);
    assign sdram_a = {13{1'b0}};
    assign sdram_dq = {16{1'bz}};
    assign sdram_ba = {2{1'b0}};
    assign sdram_clk = 1'b0;
    assign sdram_cke = 1'b0;
    assign sdram_dqm = {2{1'b1}};
    assign sdram_cs_n = 1'b1;
    assign sdram_ras_n = 1'b1;
    assign sdram_cas_n = 1'b1;
    assign sdram_we_n = 1'b1;
    assign sd_sck = 1'b0;
    assign sd_mosi = 1'b1;
    assign sd_cs_n = 1'b1;
    assign audio_l = {6{1'b0}};
    assign audio_r = {6{1'b0}};
    assign joy1_strobe = 1'b0;
    assign joy2_strobe = 1'b0;
    assign cart_sltsl2_n = 1'b1;
    assign cart_cs1_n = 1'b1;
    assign cart_cs2_n = 1'b1;
    assign cart_cs12_n = 1'b1;
    assign cart_sltsl1_n = 1'b1;
    assign cart_rfsh_n = 1'b1;
    assign cart_m1_n = 1'b1;
    assign cart_iorq_n = 1'b1;
    assign cart_merq_n = 1'b1;
    assign cart_wr_n = 1'b1;
    assign cart_rd_n = 1'b1;
    assign cart_clock_out = 1'b0;

    wire clk_4x;
    wire pll_locked;
    wire lock_reset_n;
    reg lock_sampled;
    reg video_reset_n;

    // Cyclone I fabric clock at 85.90908 MHz. No divided clock is routed.
    wire [5:0] pll_clocks;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [4:0] unused_pll_clocks;
    /* verilator lint_on UNUSEDSIGNAL */
    assign {unused_pll_clocks, clk_4x} = pll_clocks;

    altpll #(
        .intended_device_family("Cyclone"),
        .operation_mode("NORMAL"),
        .compensate_clock("CLK0"),
        .inclk0_input_frequency(46561),
        .clk0_multiply_by(4),
        .clk0_divide_by(1),
        .clk0_duty_cycle(50),
        .clk0_phase_shift("0"),
        .width_clock(6),
        .port_areset("PORT_USED"),
        .port_locked("PORT_USED"),
        .port_clk0("PORT_USED")
    ) pixel_pll (
        .inclk({1'b0, clk_21m}),
        .areset(~cart_reset_n),
        .clk(pll_clocks),
        .locked(pll_locked)
    );

    // Assert immediately on board reset or loss of PLL lock.
    // Deassert after two good fabric clock edges.
    assign lock_reset_n = cart_reset_n & pll_locked;
    always @(posedge clk_4x or negedge lock_reset_n) begin
        if (!lock_reset_n) begin
            lock_sampled <= 1'b0;
            video_reset_n <= 1'b0;
        end else begin
            lock_sampled <= 1'b1;
            video_reset_n <= lock_sampled;
        end
    end

    // 512 visible pixels, 16 front porch, 80 sync, 80 back porch.
    // 480 visible lines, 10 front porch, 2 sync, 33 back porch.
    // Pixel enable at 21.47727 MHz gives 31.217 kHz and 59.461 Hz.
    reg [1:0] pixel_phase;
    reg [9:0] raster_x;
    reg [9:0] raster_y;
    wire visible;
    wire [2:0] bar_color;
    assign visible = (raster_x < 10'd512) && (raster_y < 10'd480);
    assign bar_color = ~raster_x[8:6];

    always @(posedge clk_4x or negedge video_reset_n) begin
        if (!video_reset_n) begin
            pixel_phase <= 2'd0;
            raster_x <= 10'd0;
            raster_y <= 10'd0;
            vga_hs_n <= 1'b1;
            vga_vs_n <= 1'b1;
            vga_r <= 6'd0;
            vga_g <= 6'd0;
            vga_b <= 6'd0;
        end else begin
            pixel_phase <= pixel_phase + 2'd1;
            if (pixel_phase == 2'd3) begin
                vga_hs_n <= !((raster_x >= 10'd528) && (raster_x < 10'd608));
                vga_vs_n <= !((raster_y >= 10'd490) && (raster_y < 10'd492));
                vga_r <= {6{visible & bar_color[0]}};
                vga_g <= {6{visible & bar_color[1]}};
                vga_b <= {6{visible & bar_color[2]}};

                if (raster_x == 10'd687) begin
                    raster_x <= 10'd0;
                    if (raster_y == 10'd524)
                        raster_y <= 10'd0;
                    else
                        raster_y <= raster_y + 10'd1;
                end else begin
                    raster_x <= raster_x + 10'd1;
                end
            end
        end
    end
endmodule
