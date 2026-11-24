`timescale 1ps/1ps

module sim_bringup_tb;
    reg clk_21m;
    reg reset_n;
    tri ext_clk = 1'bz;
    wire [12:0] sdram_a;
    tri [15:0] sdram_dq;
    wire [1:0] sdram_ba;
    wire sdram_clk;
    wire sdram_cke;
    wire [1:0] sdram_dqm;
    wire sdram_cs_n;
    wire sdram_ras_n;
    wire sdram_cas_n;
    wire sdram_we_n;
    tri sd_dat1 = 1'bz;
    tri sd_miso = 1'bz;
    wire sd_sck;
    wire sd_mosi;
    wire sd_cs_n;
    tri sd_dat2 = 1'bz;
    tri ps2_data = 1'bz;
    tri ps2_clk = 1'bz;
    tri ddc_sda = 1'bz;
    wire vga_vs_n;
    wire vga_hs_n;
    tri ddc_scl = 1'bz;
    wire [5:0] vga_r;
    wire [5:0] vga_g;
    wire [5:0] vga_b;
    wire [5:0] audio_l;
    wire [5:0] audio_r;
    tri joy1_up = 1'bz;
    tri joy1_down = 1'bz;
    tri joy1_left = 1'bz;
    tri joy1_right = 1'bz;
    tri joy1_a = 1'bz;
    tri joy1_b = 1'bz;
    wire joy1_strobe;
    tri joy2_up = 1'bz;
    tri joy2_down = 1'bz;
    tri joy2_left = 1'bz;
    tri joy2_right = 1'bz;
    tri joy2_a = 1'bz;
    tri joy2_b = 1'bz;
    wire joy2_strobe;
    wire cart_sltsl2_n;
    wire cart_cs1_n;
    wire cart_cs2_n;
    wire cart_cs12_n;
    wire cart_sltsl1_n;
    tri cart_rsv5 = 1'bz;
    wire cart_rfsh_n;
    tri cart_wait_n = 1'bz;
    tri cart_int_n = 1'bz;
    wire cart_m1_n;
    tri cart_bdir = 1'bz;
    wire cart_iorq_n;
    wire cart_merq_n;
    wire cart_wr_n;
    wire cart_rd_n;
    tri cart_rsv16 = 1'bz;
    tri cart_a9 = 1'bz;
    tri cart_a15 = 1'bz;
    tri cart_a11 = 1'bz;
    tri cart_a10 = 1'bz;
    wire cart_clock_out;
    tri cart_clock_return = 1'bz;
    tri cart_a7 = 1'bz;
    tri cart_a6 = 1'bz;
    tri cart_a12 = 1'bz;
    tri cart_a8 = 1'bz;
    tri cart_a14 = 1'bz;
    tri cart_a13 = 1'bz;
    tri cart_a1 = 1'bz;
    tri cart_a0 = 1'bz;
    tri cart_a3 = 1'bz;
    tri cart_a2 = 1'bz;
    tri cart_a5 = 1'bz;
    tri cart_a4 = 1'bz;
    tri cart_d1 = 1'bz;
    tri cart_d0 = 1'bz;
    tri cart_d3 = 1'bz;
    tri cart_d2 = 1'bz;
    tri cart_d5 = 1'bz;
    tri cart_d4 = 1'bz;
    tri cart_d7 = 1'bz;
    tri cart_d6 = 1'bz;
    tri cart_sw1 = 1'bz;
    tri cart_sw2 = 1'bz;
    tri esp_txd = 1'bz;
    tri esp_rxd = 1'bz;
    tri unused_238 = 1'bz;
    tri unused_239 = 1'bz;

    trhmsx_bringup_top dut (
        .clk_21m(clk_21m),
        .ext_clk(ext_clk),
        .sdram_a(sdram_a),
        .sdram_dq(sdram_dq),
        .sdram_ba(sdram_ba),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_dqm(sdram_dqm),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sd_dat1(sd_dat1),
        .sd_miso(sd_miso),
        .sd_sck(sd_sck),
        .sd_mosi(sd_mosi),
        .sd_cs_n(sd_cs_n),
        .sd_dat2(sd_dat2),
        .ps2_data(ps2_data),
        .ps2_clk(ps2_clk),
        .ddc_sda(ddc_sda),
        .vga_vs_n(vga_vs_n),
        .vga_hs_n(vga_hs_n),
        .ddc_scl(ddc_scl),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .audio_l(audio_l),
        .audio_r(audio_r),
        .joy1_up(joy1_up),
        .joy1_down(joy1_down),
        .joy1_left(joy1_left),
        .joy1_right(joy1_right),
        .joy1_a(joy1_a),
        .joy1_b(joy1_b),
        .joy1_strobe(joy1_strobe),
        .joy2_up(joy2_up),
        .joy2_down(joy2_down),
        .joy2_left(joy2_left),
        .joy2_right(joy2_right),
        .joy2_a(joy2_a),
        .joy2_b(joy2_b),
        .joy2_strobe(joy2_strobe),
        .cart_sltsl2_n(cart_sltsl2_n),
        .cart_cs1_n(cart_cs1_n),
        .cart_cs2_n(cart_cs2_n),
        .cart_cs12_n(cart_cs12_n),
        .cart_sltsl1_n(cart_sltsl1_n),
        .cart_rsv5(cart_rsv5),
        .cart_rfsh_n(cart_rfsh_n),
        .cart_wait_n(cart_wait_n),
        .cart_int_n(cart_int_n),
        .cart_m1_n(cart_m1_n),
        .cart_bdir(cart_bdir),
        .cart_iorq_n(cart_iorq_n),
        .cart_merq_n(cart_merq_n),
        .cart_wr_n(cart_wr_n),
        .cart_rd_n(cart_rd_n),
        .cart_rsv16(cart_rsv16),
        .cart_a9(cart_a9),
        .cart_a15(cart_a15),
        .cart_a11(cart_a11),
        .cart_a10(cart_a10),
        .cart_clock_out(cart_clock_out),
        .cart_clock_return(cart_clock_return),
        .cart_reset_n(reset_n),
        .cart_a7(cart_a7),
        .cart_a6(cart_a6),
        .cart_a12(cart_a12),
        .cart_a8(cart_a8),
        .cart_a14(cart_a14),
        .cart_a13(cart_a13),
        .cart_a1(cart_a1),
        .cart_a0(cart_a0),
        .cart_a3(cart_a3),
        .cart_a2(cart_a2),
        .cart_a5(cart_a5),
        .cart_a4(cart_a4),
        .cart_d1(cart_d1),
        .cart_d0(cart_d0),
        .cart_d3(cart_d3),
        .cart_d2(cart_d2),
        .cart_d5(cart_d5),
        .cart_d4(cart_d4),
        .cart_d7(cart_d7),
        .cart_d6(cart_d6),
        .cart_sw1(cart_sw1),
        .cart_sw2(cart_sw2),
        .esp_txd(esp_txd),
        .esp_rxd(esp_rxd),
        .unused_238(unused_238),
        .unused_239(unused_239)
    );

    task fail;
        input [8*80-1:0] reason;
        begin
            $display("FAIL: %0s at %0t", reason, $time);
            $stop;
        end
    endtask

    task check_safe_pads;
        begin
            if ({ext_clk, sdram_dq, sd_dat1, sd_miso,
                 sd_dat2, ps2_data, ps2_clk, ddc_sda,
                 ddc_scl, joy1_up, joy1_down, joy1_left,
                 joy1_right, joy1_a, joy1_b, joy2_up,
                 joy2_down, joy2_left, joy2_right, joy2_a,
                 joy2_b, cart_rsv5, cart_wait_n, cart_int_n,
                 cart_bdir, cart_rsv16, cart_a9, cart_a15,
                 cart_a11, cart_a10, cart_clock_return, cart_a7,
                 cart_a6, cart_a12, cart_a8, cart_a14,
                 cart_a13, cart_a1, cart_a0, cart_a3,
                 cart_a2, cart_a5, cart_a4, cart_d1,
                 cart_d0, cart_d3, cart_d2, cart_d5,
                 cart_d4, cart_d7, cart_d6, cart_sw1,
                 cart_sw2, esp_txd, esp_rxd, unused_238,
                 unused_239} !== {72{1'bz}})
                fail("released pads drive a level");
            if ({sdram_dqm, sdram_cs_n, sdram_ras_n, sdram_cas_n,
                 sdram_we_n, sd_mosi, sd_cs_n, cart_sltsl2_n,
                 cart_cs1_n, cart_cs2_n, cart_cs12_n, cart_sltsl1_n,
                 cart_rfsh_n, cart_m1_n, cart_iorq_n, cart_merq_n,
                 cart_wr_n, cart_rd_n} !== {19{1'b1}})
                fail("idle-high output is not high");
            if ({sdram_a, sdram_ba, sdram_clk, sdram_cke,
                 sd_sck, audio_l, audio_r, joy1_strobe,
                 joy2_strobe, cart_clock_out} !== {33{1'b0}})
                fail("idle-low output is not low");
        end
    endtask

    task check_reset_video;
        begin
            if ({vga_hs_n, vga_vs_n, vga_r, vga_g, vga_b} !== {2'b11, 18'd0})
                fail("reset video is not black with inactive sync");
        end
    endtask

    time hs_fall;
    initial begin
        @(posedge reset_n);
        @(negedge vga_hs_n);
        hs_fall = $time;
        @(posedge vga_hs_n);
        if ($time - hs_fall != 64'd3724800)
            fail("horizontal sync pulse width");
        @(negedge vga_hs_n);
        if ($time - hs_fall != 64'd32033280)
            fail("horizontal line period");
    end

    time vs_fall;
    initial begin
        @(posedge reset_n);
        @(negedge vga_vs_n);
        vs_fall = $time;
        @(posedge vga_vs_n);
        if ($time - vs_fall != 64'd64066560)
            fail("vertical sync pulse width");
    end

    // The source period is 46560 ps at the simulation precision.
    initial begin
        clk_21m = 1'b0;
        forever #23280 clk_21m = ~clk_21m;
    end

    integer x;
    integer y;
    reg [2:0] expected;
    time first_pixel;
    initial begin
        reset_n = 1'b0;
        repeat (8) @(negedge clk_21m);
        check_reset_video;
        check_safe_pads;
        reset_n = 1'b1;

        // Start with the first white pixel. Check every pixel through a
        // full frame and its wrap without using the DUT's counters.
        wait ({vga_r, vga_g, vga_b} === {18{1'b1}});
        first_pixel = $time;
        #1;
        for (y = 0; y < 525; y = y + 1) begin
            for (x = 0; x < 688; x = x + 1) begin
                if (vga_hs_n !== ((x < 528) || (x >= 608)))
                    fail("horizontal sync polarity or timing");
                if (vga_vs_n !== ((y < 490) || (y >= 492)))
                    fail("vertical sync polarity or timing");
                expected = 3'b000;
                if (y < 480) begin
                    case (x / 64)
                        0: expected = 3'b111;
                        1: expected = 3'b110;
                        2: expected = 3'b101;
                        3: expected = 3'b100;
                        4: expected = 3'b011;
                        5: expected = 3'b010;
                        6: expected = 3'b001;
                        default: expected = 3'b000;
                    endcase
                end
                if ({vga_b, vga_g, vga_r} !==
                    {{6{expected[2]}}, {6{expected[1]}}, {6{expected[0]}}})
                    fail("color bars or blanking");
                #46560;
            end
            check_safe_pads;
        end
        if ($time - first_pixel != 64'd16817472001)
            fail("frame period");
        if ({vga_hs_n, vga_vs_n, vga_r, vga_g, vga_b} !== {20{1'b1}})
            fail("frame wrap");

        // Reset off the clock edge while a visible pixel is being driven.
        #100 reset_n = 1'b0;
        #1;
        check_reset_video;
        check_safe_pads;
        repeat (8) @(negedge clk_21m);
        reset_n = 1'b1;
        wait ({vga_r, vga_g, vga_b} === {18{1'b1}});
        $display("PASS: VGA bars, sync and frame timing, reset, and idle pads");
        $finish;
    end

    initial begin
        #(64'd20000000000);
        fail("test timed out");
    end
endmodule

// Local timing model of the ALTPLL ports used by the board top.
// Quartus loads only the board top and binds the device megafunction.
/* verilator lint_off DECLFILENAME */
module altpll #(
    parameter intended_device_family = "Cyclone",
    parameter operation_mode = "NORMAL",
    parameter compensate_clock = "CLK0",
    parameter inclk0_input_frequency = 46561,
    parameter clk0_multiply_by = 4,
    parameter clk0_divide_by = 1,
    parameter clk0_duty_cycle = 50,
    parameter clk0_phase_shift = "0",
    parameter width_clock = 6,
    parameter port_areset = "PORT_USED",
    parameter port_locked = "PORT_USED",
    parameter port_clk0 = "PORT_USED"
) (
    input wire [1:0] inclk,
    input wire areset,
    output wire [width_clock-1:0] clk,
    output wire locked
);
    localparam HALF_PERIOD_PS = inclk0_input_frequency * clk0_divide_by /
                               (2 * clk0_multiply_by);
    reg fast_clk;
    reg [2:0] lock_edges;

    assign clk = {{(width_clock-1){1'b0}}, fast_clk};
    assign locked = lock_edges[2];

    initial begin
        if (intended_device_family != "Cyclone" || operation_mode != "NORMAL" ||
            compensate_clock != "CLK0" || clk0_duty_cycle != 50 ||
            clk0_phase_shift != "0" || port_areset != "PORT_USED" ||
            port_locked != "PORT_USED" || port_clk0 != "PORT_USED") begin
            $display("FAIL: ALTPLL parameters unsupported by the simulation model");
            $stop;
        end
        fast_clk = 1'b0;
        forever #(HALF_PERIOD_PS) fast_clk = ~fast_clk;
    end

    always @(posedge inclk[0] or posedge areset) begin
        if (areset || inclk[1])
            lock_edges <= 3'b000;
        else
            lock_edges <= {lock_edges[1:0], 1'b1};
    end
endmodule
/* verilator lint_on DECLFILENAME */
