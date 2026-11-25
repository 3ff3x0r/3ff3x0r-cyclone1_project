module trhmsx_mem_fit_top (
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

    wire clk_sys;
    wire pll_locked;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [5:0] pll_clocks;
    wire [3:0] pll_ext_clocks;
    /* verilator lint_on UNUSEDSIGNAL */
    assign clk_sys = pll_clocks[0];
    assign sdram_clk = pll_ext_clocks[0];

    // PLL1 drives the fabric on c0 and the dedicated U1-38 pad on e0.
    altpll #(
        .intended_device_family("Cyclone"),
        .operation_mode("NORMAL"),
        .compensate_clock("CLK0"),
        .inclk0_input_frequency(46561),
        .clk0_multiply_by(4),
        .clk0_divide_by(1),
        .clk0_duty_cycle(50),
        .clk0_phase_shift("0"),
        .extclk0_multiply_by(4),
        .extclk0_divide_by(1),
        .extclk0_duty_cycle(50),
        .extclk0_phase_shift("-3000"),
        .width_clock(6),
        .port_inclk0("PORT_USED"),
        .port_areset("PORT_USED"),
        .port_locked("PORT_USED"),
        .port_clk0("PORT_USED"),
        .port_extclk0("PORT_USED")
    ) memory_pll (
        .inclk({1'b0, clk_21m}),
        .areset(~cart_reset_n),
        .clk(pll_clocks),
        .extclk(pll_ext_clocks),
        .locked(pll_locked)
    );

    wire lock_reset_n = cart_reset_n & pll_locked;
    reg lock_sampled;
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

    wire mem_ready;
    wire mem_idle;
    wire cpu_mem_req;
    wire cpu_mem_accept;
    wire [21:0] cpu_mem_addr;
    wire [7:0] cpu_mem_wdata;
    wire cpu_mem_rvalid;
    wire [7:0] cpu_mem_rdata;
    wire ld_mem_req;
    wire ld_mem_accept;
    wire [21:0] ld_mem_addr;
    wire [7:0] ld_mem_wdata;
    wire ld_mem_rvalid;
    wire [7:0] ld_mem_rdata;
    wire screen_rd_req;
    reg screen_rd_bank7;
    wire screen_rd_valid;
    wire [7:0] screen_rd_data;
    reg [12:0] offset;

    localparam [2:0] WRITE_PAIR   = 3'd0,
                     DRAIN_WRITES = 3'd1,
                     READ_PAIR    = 3'd2,
                     SCREEN_REQ   = 3'd3,
                     SCREEN_WAIT  = 3'd4,
                     NEXT_BYTE    = 3'd5;
    reg [2:0] state;
    reg cpu_accepted;
    reg ld_accepted;
    reg cpu_read_done;
    reg ld_read_done;
    reg general_sweep;
    reg invert_pattern;
    reg [7:0] cpu_sample;
    reg [7:0] ld_sample;
    reg [7:0] screen_sample;
    reg test_failed;

    wire writing = (state == WRITE_PAIR);
    wire issue_pair = writing || (state == READ_PAIR);
    wire cpu_bank7 = offset[1];
    wire [21:0] bank5_addr = {8'd5, 1'b0, offset};
    wire [21:0] bank7_addr = {8'd7, 1'b0, offset};
    // Span the lower 4 MiB outside the screen banks. Pair adjacent byte
    // lanes in each SDRAM word so one writer can expose a DQM error in the other.
    wire [21:0] general_addr = {offset[3:2], 1'b1, offset[6:1], offset};
    assign cpu_mem_addr = general_sweep ? general_addr : (cpu_bank7 ? bank7_addr : bank5_addr);
    assign ld_mem_addr = general_sweep ? (general_addr ^ 22'd1) : (cpu_bank7 ? bank5_addr : bank7_addr);
    assign cpu_mem_wdata = offset[7:0] ^ {3'b101, offset[12:8]} ^ {8{invert_pattern}};
    assign ld_mem_wdata = ~cpu_mem_wdata;
    assign cpu_mem_req = mem_ready && issue_pair && !cpu_accepted;
    assign ld_mem_req = mem_ready && issue_pair && !ld_accepted;
    assign screen_rd_req = (state == SCREEN_REQ);
    wire [7:0] screen_expected = (screen_rd_bank7 == cpu_bank7) ? cpu_mem_wdata : ld_mem_wdata;

    mem_subsystem memory (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .mem_ready(mem_ready),
        .mem_idle(mem_idle),
        .cpu_mem_req(cpu_mem_req),
        .cpu_mem_accept(cpu_mem_accept),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_we(writing),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rvalid(cpu_mem_rvalid),
        .cpu_mem_rdata(cpu_mem_rdata),
        .ld_mem_req(ld_mem_req),
        .ld_mem_accept(ld_mem_accept),
        .ld_mem_addr(ld_mem_addr),
        .ld_mem_we(writing),
        .ld_mem_wdata(ld_mem_wdata),
        .ld_mem_rvalid(ld_mem_rvalid),
        .ld_mem_rdata(ld_mem_rdata),
        .screen_rd_req(screen_rd_req),
        .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(offset),
        .screen_rd_valid(screen_rd_valid),
        .screen_rd_data(screen_rd_data),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_a(sdram_a),
        .sdram_ba(sdram_ba),
        .sdram_dqm(sdram_dqm),
        .sdram_dq(sdram_dq)
    );

    // Both clients start together and hold their request until acceptance.
    // Drain the writes before reading SDRAM and both screen mirror banks.
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state <= WRITE_PAIR;
            cpu_accepted <= 1'b0;
            ld_accepted <= 1'b0;
            cpu_read_done <= 1'b0;
            ld_read_done <= 1'b0;
            screen_rd_bank7 <= 1'b0;
            offset <= 13'd0;
            general_sweep <= 1'b0;
            invert_pattern <= 1'b0;
            cpu_sample <= 8'd0;
            ld_sample <= 8'd0;
            screen_sample <= 8'd0;
            test_failed <= 1'b0;
        end else begin
            if (cpu_mem_req && cpu_mem_accept)
                cpu_accepted <= 1'b1;
            if (ld_mem_req && ld_mem_accept)
                ld_accepted <= 1'b1;

            case (state)
                WRITE_PAIR: begin
                    if (cpu_accepted && ld_accepted)
                        state <= DRAIN_WRITES;
                end
                DRAIN_WRITES: begin
                    if (mem_idle) begin
                        cpu_accepted <= 1'b0;
                        ld_accepted <= 1'b0;
                        cpu_read_done <= 1'b0;
                        ld_read_done <= 1'b0;
                        state <= READ_PAIR;
                    end
                end
                READ_PAIR: begin
                    if (cpu_mem_rvalid) begin
                        cpu_read_done <= 1'b1;
                        cpu_sample <= cpu_mem_rdata;
                        if (cpu_mem_rdata != cpu_mem_wdata)
                            test_failed <= 1'b1;
                    end
                    if (ld_mem_rvalid) begin
                        ld_read_done <= 1'b1;
                        ld_sample <= ld_mem_rdata;
                        if (ld_mem_rdata != ld_mem_wdata)
                            test_failed <= 1'b1;
                    end
                    if (cpu_read_done && ld_read_done)
                        state <= general_sweep ? NEXT_BYTE : SCREEN_REQ;
                end
                SCREEN_REQ: state <= SCREEN_WAIT;
                SCREEN_WAIT: begin
                    if (screen_rd_valid) begin
                        screen_sample <= screen_rd_data;
                        if (screen_rd_data != screen_expected)
                            test_failed <= 1'b1;
                        screen_rd_bank7 <= ~screen_rd_bank7;
                        state <= screen_rd_bank7 ? NEXT_BYTE : SCREEN_REQ;
                    end
                end
                NEXT_BYTE: begin
                    if (offset == 13'd6911) begin
                        offset <= 13'd0;
                        general_sweep <= ~general_sweep;
                        if (general_sweep)
                            invert_pattern <= ~invert_pattern;
                    end else begin
                        offset <= offset + 13'd1;
                    end
                    cpu_accepted <= 1'b0;
                    ld_accepted <= 1'b0;
                    state <= WRITE_PAIR;
                end
                default: state <= NEXT_BYTE;
            endcase
        end
    end

    // Use the bring-up raster with a 21.47727 MHz pixel enable.
    // RGB bit 5 shows sticky mismatch, ready and idle, respectively.
    // Lower bits fold all eight bits of the last CPU, loader and mirror reads.
    reg [1:0] pixel_phase;
    reg [9:0] raster_x;
    reg [9:0] raster_y;
    wire visible = (raster_x < 10'd512) && (raster_y < 10'd480);
    wire [4:0] cpu_color = cpu_sample[4:0] ^ {cpu_sample[7:5], 2'b00};
    wire [4:0] ld_color = ld_sample[4:0] ^ {ld_sample[7:5], 2'b00};
    wire [4:0] screen_color = screen_sample[4:0] ^ {screen_sample[7:5], 2'b00};

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
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
                vga_r <= visible ? {test_failed, cpu_color} : 6'd0;
                vga_g <= visible ? {mem_ready, ld_color} : 6'd0;
                vga_b <= visible ? {mem_idle, screen_color} : 6'd0;

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
