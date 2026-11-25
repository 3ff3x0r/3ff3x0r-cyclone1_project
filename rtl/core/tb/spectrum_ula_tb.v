`timescale 1ns/1ps

module spectrum_ula_tb;
    reg clk_sys = 0;
    always #5 clk_sys = !clk_sys;
    reg rst_n = 0, run = 0;
    reg [1:0] tick = 0;
    always @(negedge clk_sys) tick = tick + 2'd1;
    wire ce_ula = !tick[0];
    wire ce_cpu = tick == 2'd2;

    reg [2:0] timing_id = 0, ula_contend_id = 0, ula_bus_ram_bank = 0;
    reg [2:0] border = 3'd5;
    reg bank7 = 0, ula_bus_valid = 1, ula_bus_is_ram = 1;
    wire screen_rd_req, screen_rd_bank7, ula_px_ce;
    wire [12:0] screen_rd_offset;
    reg screen_read_sampled = 0, screen_rd_valid = 0;
    reg [7:0] screen_data_sampled;
    reg [7:0] screen_rd_data;
    wire [3:0] ula_color;
    wire [9:0] ula_x;
    wire [8:0] ula_y;
    wire ula_hs_n, ula_vs_n, ula_blank, int_n, bus_contended;
    wire [2:0] raster_delay;
    wire [7:0] floating_bus, asic_bus;
    reg contended_transfer = 0;

    spectrum_ula dut (
        .clk_sys(clk_sys), .rst_n(rst_n), .run(run), .ce_cpu(ce_cpu), .ce_ula(ce_ula),
        .timing_id(timing_id), .border(border), .screen_bank7(bank7),
        .screen_rd_req(screen_rd_req), .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(screen_rd_offset), .screen_rd_valid(screen_rd_valid),
        .screen_rd_data(screen_rd_data), .ula_px_ce(ula_px_ce), .ula_color(ula_color),
        .ula_x(ula_x), .ula_y(ula_y), .ula_hs_n(ula_hs_n), .ula_vs_n(ula_vs_n),
        .ula_blank(ula_blank), .int_n(int_n), .ula_bus_valid(ula_bus_valid),
        .ula_bus_is_ram(ula_bus_is_ram), .ula_bus_ram_bank(ula_bus_ram_bank),
        .ula_contend_id(ula_contend_id), .contended_transfer(contended_transfer),
        .transfer_data(8'h66), .bus_contended(bus_contended), .raster_delay(raster_delay),
        .floating_bus(floating_bus), .asic_bus(asic_bus)
    );

    integer expected_rd, observed_rd;
    integer picture_start, picture_left, xblank, xhs, yvs, vs_height, vblank_height, yint, xint, irq_width;
    integer fetch_start, contention_start, width, height;
    integer phase, delay, row, col, expected_addr;
    integer x, y, sample;
    reg [3:0] expected_pixel;
    reg [7:0] expected_bus;
    reg visible, hsync, vsync, irq;
    // Mirror fixture distinguishes bank, bitmap and attribute. Even
    // columns have leftmost and rightmost bits set. Odd columns invert them.
    function [7:0] mirror_byte;
        input bank;
        input attribute;
        input odd;
        begin
            if (attribute)
                mirror_byte = bank ? 8'h23 : 8'h55;
            else
                mirror_byte = odd ? 8'h7e : 8'h81;
        end
    endfunction
    always @(posedge clk_sys) begin
        screen_read_sampled <= screen_rd_req;
        screen_rd_valid <= screen_read_sampled;
        screen_rd_data <= screen_data_sampled;
        if (screen_rd_req)
            screen_data_sampled <= mirror_byte(screen_rd_bank7, screen_rd_offset >= 6144, screen_rd_offset[0]);
    end

    task check_membership;
        input integer id;
        input integer physical_bank;
        reg expected;
        begin
            case (id)
                1, 4, 5: expected = physical_bank == 5;
                2: expected = physical_bank % 2 == 1;
                3: expected = physical_bank >= 4;
                default: expected = 0;
            endcase
            @(negedge clk_sys);
            ula_contend_id = id;
            ula_bus_ram_bank = physical_bank;
            @(posedge clk_sys);
            if (bus_contended !== expected) begin
                $display("FAIL Bank contention id=%0d physical_bank=%0d", id, physical_bank);
                $finish;
            end
        end
    endtask

    task check_frame;
        input integer model;
        begin
            @(negedge clk_sys);
            run = 0;
            timing_id = model;
            bank7 = model % 2;
            width = 448; height = 312; picture_start = 56; picture_left = 48;
            xblank = 344; xhs = 368; yvs = 296; vs_height = 4; vblank_height = 4;
            yint = 304; xint = 48; irq_width = 64; fetch_start = 52; contention_start = 46;
            case (model)
                0: ula_contend_id = 1;
                1, 2: begin
                    width = 456; height = 311; xhs = 372;
                    irq_width = model == 1 ? 72 : 64;
                    xint = model == 1 ? 52 : 46;
                    contention_start = model == 1 ? 46 : 40;
                    ula_contend_id = model + 1;
                end
                3, 4: begin
                    width = 456; height = model == 3 ? 312 : 262;
                    picture_start = model == 3 ? 56 : 32; picture_left = 52;
                    xblank = 360; xhs = 380; yvs = model == 3 ? 304 : 256;
                    yint = yvs - 1; xint = 315; fetch_start = 57; contention_start = 42;
                    vblank_height = 8;
                    ula_contend_id = model + 1;
                end
                5: begin
                    height = 320; picture_start = 64; picture_left = 44; xblank = 340; xhs = 366;
                    yvs = 312; vs_height = 8; vblank_height = 8;
                    yint = 303; xint = 356; irq_width = 72; fetch_start = 44;
                    ula_contend_id = 0;
                end
            endcase
            repeat (3) @(negedge clk_sys);
            run = 1;
            observed_rd = 0;
            for (sample = 0; sample < width * height + 1; sample = sample + 1) begin
                @(posedge clk_sys);
                while (!ula_px_ce)
                    @(posedge clk_sys);
                x = sample % width;
                y = (sample / width) % height;
                hsync = !(x >= xhs && x < xhs + 32);
                vsync = !(y >= yvs && y < yvs + vs_height);
                irq = !(y == yint && x >= xint && x < xint + irq_width);
                visible = x < xblank && !(y >= yvs && y < yvs + vblank_height);
                if (ula_x !== x || ula_y !== y || ula_hs_n !== hsync || ula_vs_n !== vsync ||
                    ula_blank !== !visible || int_n !== irq) begin
                    $display("FAIL Raster/sync/blank/INT model=%d x=%d y=%d", model, x, y);
                    $finish;
                end
                row = y - picture_start;
                expected_pixel = visible ? {1'b0, border} : 4'd0;
                if ((row >= 0 && row < 192) && (x >= picture_left && x < picture_left + 256)) begin
                    col = x - picture_left;
                    case ({bank7, (((col % 8) == 0 || (col % 8) == 7) ^ ((col / 8) % 2 == 1))})
                        2'b00: expected_pixel = 4'ha;
                        2'b01: expected_pixel = 4'hd;
                        2'b10: expected_pixel = 4'h4;
                        2'b11: expected_pixel = 4'h3;
                    endcase
                end
                if (ula_color !== expected_pixel) begin
                    $display("FAIL Color model=%d x=%d y=%d expected=%h got=%h", model, x, y, expected_pixel, ula_color);
                    $finish;
                end

                phase = x - contention_start;
                delay = 0;
                if (model != 5 && row >= 0 && row < 192 && phase >= 0 && phase < 256) begin
                    phase = (phase / 2) % 8;
                    case (model)
                        2: case (phase)
                            0: delay = 1; 1: delay = 0; 2: delay = 7; 3: delay = 6;
                            4: delay = 5; 5: delay = 4; 6: delay = 3; 7: delay = 2;
                        endcase
                        default: delay = phase < 6 ? 6 - phase : 0;
                    endcase
                end
                if (raster_delay !== delay) begin
                    $display("FAIL Contention phase model=%d x=%d y=%d", model, x, y);
                    $finish;
                end

                phase = x - fetch_start;
                expected_bus = 8'hff;
                if (row >= 0 && row < 192 && phase >= 0 && phase < 256 && phase % 16 < 8)
                    expected_bus = mirror_byte(bank7, phase % 4 >= 2, phase % 16 >= 4);
                if (floating_bus !== expected_bus) begin
                    $display("FAIL Floating bus model=%d x=%d y=%d expected=%h got=%h",
                             model, x, y, expected_bus, floating_bus);
                    $finish;
                end

                phase = x - (picture_left - 8);
                expected_rd = row >= 0 && row < 192 && phase >= 0 && phase < 256 &&
                              phase % 16 < 8 && phase % 2 == 0;
                if (screen_rd_req !== expected_rd || screen_rd_bank7 !== bank7) begin
                    $display("FAIL Mirror request phase/bank model=%d x=%d y=%d", model, x, y);
                    $finish;
                end
                if (expected_rd) begin
                    observed_rd = observed_rd + 1;
                    col = (phase / 16) * 2 + (phase % 8) / 4;
                    if (phase % 4 == 2)
                        expected_addr = 6144 + (row / 8) * 32 + col;
                    else
                        expected_addr = (row / 64) * 2048 + (row % 8) * 256 +
                                        ((row / 8) % 8) * 32 + col;
                    if (screen_rd_offset !== expected_addr) begin
                        $display("FAIL Screen address x=%d y=%d expected=%d got=%d", x, y, expected_addr, screen_rd_offset);
                        $finish;
                    end
                end
            end
            if (observed_rd != 192 * 64) begin
                $display("FAIL Wrong mirror request count");
                $finish;
            end
        end
    endtask

    integer profile, bank;
    initial begin
        repeat (3) @(negedge clk_sys);
        rst_n = 1;
        for (profile = 0; profile < 6; profile = profile + 1)
            for (bank = 0; bank < 8; bank = bank + 1)
                check_membership(profile, bank);
        @(negedge clk_sys);
        ula_bus_is_ram = 0;
        ula_contend_id = 3;
        @(posedge clk_sys);
        if (bus_contended) begin
            $display("FAIL ROM/unmapped access contended");
            $finish;
        end
        @(negedge clk_sys);
        ula_bus_is_ram = 1;
        ula_bus_valid = 0;
        @(posedge clk_sys);
        if (bus_contended) begin
            $display("FAIL Idle bus contended");
            $finish;
        end
        for (profile = 0; profile < 6; profile = profile + 1)
            check_frame(profile);
        @(negedge clk_sys);
        contended_transfer = 1;
        @(negedge clk_sys);
        if (asic_bus !== 8'h66) begin
            $display("FAIL ASIC bus did not retain contended CPU data");
            $finish;
        end

        $display("PASS six ULA rasters, color, mirror addresses, sync/INT, contention and floating bus");
        $finish;
    end

    initial begin
        #30000000;
        $display("FAIL ULA timeout in timing profile %0d", timing_id);
        $finish;
    end
endmodule
