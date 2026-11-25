module trhmsx_spectrum_top #(
    parameter BOOT_ROM_FILE = ""
) (
    input  wire clk_21m,
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

    output wire vga_vs_n,
    output wire vga_hs_n,
    output wire [5:0] vga_r,
    output wire [5:0] vga_g,
    output wire [5:0] vga_b,
    output wire [5:0] audio_l,
    output wire [5:0] audio_r,

    output wire sd_sck,
    output wire sd_mosi,
    output wire sd_cs_n,
    input  wire sd_miso,
    input  wire ps2_data,
    input  wire ps2_clk,

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

    // Unused pads remain high-impedance inputs.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire ext_clk,
    input  wire sd_dat1,
    input  wire sd_dat2,
    input  wire ddc_sda,
    input  wire ddc_scl,
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

    wire clk_sys, clk_cpu;
    wire pll_locked;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [5:0] pll_clocks;
    wire [3:0] pll_ext_clocks;
    /* verilator lint_on UNUSEDSIGNAL */
    assign clk_sys = pll_clocks[0];
    assign clk_cpu = pll_clocks[1];
    assign sdram_clk = pll_ext_clocks[0];

    // PLL1 drives the fabric on c0, the CPU on c1 and the U1-38 pad on e0.
    // Reuse the standalone memory fit's 2.909 ns e0 lead. TimeQuest
    // derives both clocks for rising-edge commands and falling-edge DQ.
    altpll #(
        .intended_device_family("Cyclone"),
        .operation_mode("NORMAL"),
        .compensate_clock("CLK0"),
        .inclk0_input_frequency(46561),
        .clk0_multiply_by(4),
        .clk0_divide_by(1),
        .clk0_duty_cycle(50),
        .clk0_phase_shift("0"),
        .clk1_multiply_by(2),
        .clk1_divide_by(1),
        .clk1_duty_cycle(50),
        .clk1_phase_shift("0"),
        .extclk0_multiply_by(4),
        .extclk0_divide_by(1),
        .extclk0_duty_cycle(50),
        .extclk0_phase_shift("-2909"),
        .width_clock(6),
        .port_inclk0("PORT_USED"),
        .port_areset("PORT_USED"),
        .port_locked("PORT_USED"),
        .port_clk0("PORT_USED"),
        .port_clk1("PORT_USED"),
        .port_extclk0("PORT_USED")
    ) memory_pll (
        .inclk({1'b0, clk_21m}),
        .areset(~cart_reset_n),
        .clk(pll_clocks),
        .extclk(pll_ext_clocks),
        .locked(pll_locked)
    );

    wire lock_reset_n = cart_reset_n & pll_locked;
    // Assert on board reset or lock loss, release after two c0 edges.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg lock_sampled;
    reg rst_n;
    always @(posedge clk_sys or negedge lock_reset_n) begin
        if (!lock_reset_n) begin
            lock_sampled <= 1'b0;
            rst_n <= 1'b0;
        end else begin
            lock_sampled <= 1'b1;
            rst_n <= lock_sampled;
        end
    end

    // Native line doubling uses the c0 fabric clock for VGA scanout.
    // The board has no external loader port. Until the loader producer is
    // integrated, keep DMA and commit idle and retain boot ownership.
    spectrum_top #(.BOOT_ROM_FILE(BOOT_ROM_FILE)) spectrum (
        .clk_sys(clk_sys), .clk_cpu(clk_cpu), .rst_n(rst_n),
        .clk_vga(clk_sys), .rst_vga_n(rst_n),
        .sdram_cke(sdram_cke), .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n), .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_a(sdram_a), .sdram_ba(sdram_ba), .sdram_dqm(sdram_dqm), .sdram_dq(sdram_dq),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs_n(vga_hs_n), .vga_vs_n(vga_vs_n), .vga_blank(),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .joy1_n({joy1_b, joy1_a, joy1_right, joy1_left, joy1_down, joy1_up}),
        .joy2_n({joy2_b, joy2_a, joy2_right, joy2_left, joy2_down, joy2_up}),
        .audio_l(audio_l), .audio_r(audio_r),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .pending_profile_id(4'd0), .pending_ram_size_id(2'd0),
        .pending_timing_id(3'd0), .pending_paging_id(3'd0), .pending_rom_set_id(16'd0),
        .pending_rom_valid_mask(4'd0), .pending_psg_enable(1'b0), .pending_disk_kind(2'd0),
        .pending_input_map_id(2'd0), .pending_joy1_b_map(2'd0), .pending_joy2_b_map(2'd0),
        .boot_commit_valid(1'b0), .boot_commit_ready(),
        .boot_stage_ok(1'b0), .boot_ram_init_ok(1'b0),
        .boot_publish(), .boot_commit_done(), .boot_error(), .boot_recovery(),
        .loader_diag_active(1'b0), .loader_diag_code(8'd0),
        .ext_ld_mem_req(1'b0), .ext_ld_mem_accept(), .ext_ld_mem_addr(22'd0),
        .ext_ld_mem_we(1'b0), .ext_ld_mem_wdata(8'd0),
        .ext_ld_mem_rvalid(), .ext_ld_mem_rdata(),
        .mem_ready(), .clocks_ready(), .boot_overlay(), .cfg_valid(), .cpu_mem_deadline_miss()
    );
endmodule
