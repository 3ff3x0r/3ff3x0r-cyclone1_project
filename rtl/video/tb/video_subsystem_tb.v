`timescale 1ns/1fs

module video_subsystem_tb;
    localparam integer SYS_HZ = 85909080;
    localparam real SYS_HALF_NS = 500000000.0 / SYS_HZ;
    localparam real VGA_HALF_NS = 500000000.0 / 25175000.0;
    localparam integer WIDTH = 448;
    localparam integer HEIGHT = 312;

    reg clk_sys = 1'b0;
    reg clk_skew = 1'b0;
    always #(SYS_HALF_NS) clk_sys = ~clk_sys;
    initial begin
        #7.317;
        forever #(VGA_HALF_NS) clk_skew = ~clk_skew;
    end
    wire [1:0] clk_vga = {clk_skew, clk_sys};

    reg rst_n = 1'b1;
    reg [1:0] rst_vga_n = 2'b11;
    reg restart_raster = 1'b1;
    reg [1:0] check_scan = 2'b00;
    reg short_scan = 1'b0;
    wire [1:0] scan_done;
    wire [1:0] clocks_ready;
    wire [1:0] ce_ula;
    wire [1:0] ce_cpu;
    wire [1:0] ce_psg;
    wire [1:0] hs_n;
    wire [1:0] vs_n;
    wire [1:0] blank;
    wire [17:0] rgb [0:1];
    wire rates_done;
    wire alternate_rate_done;
    reg clk_80m = 1'b0;
    always #6.25 if (!alternate_rate_done) clk_80m = ~clk_80m;

    reg [9:0] x;
    reg [8:0] y;
    integer frame;
    wire px_ce = ce_ula[0] && !restart_raster;
    wire [3:0] guest_color = x[3:0] + y[3:0] + frame[3:0];
    wire guest_hs_n = (x < 390 || x >= 422);
    // Deliberately change VS inside a line to check line-aligned VGA VS.
    wire guest_vs_n = !((y == 300 && x >= 123) || (y > 300 && y < 304) ||
                        (y == 304 && x < 123));
    wire guest_blank = x < 24 || x >= 376 || y < 4 || y >= 292;
    wire loader_active = (frame != 0 || y >= 5);
    wire [7:0] loader_code = (frame == 1 && y < 6) ? 8'ha6 : 8'h59;

    always @(posedge clk_sys) begin
        if (restart_raster) begin
            x <= 0;
            y <= 0;
            frame <= 0;
        end else if (px_ce) begin
            if (x == WIDTH - 1) begin
                x <= 0;
                if (y == HEIGHT - 1) begin
                    y <= 0;
                    frame <= frame + 1;
                end else begin
                    y <= y + 1'b1;
                end
            end else begin
                x <= x + 1'b1;
            end
        end
    end

    genvar output_index;
    generate
        for (output_index = 0; output_index < 2; output_index = output_index + 1) begin : outputs
            video_subsystem dut (
                .clk_sys(clk_sys), .rst_n(rst_n),
                .cfg_timing_id(3'd0), .cfg_psg_enable(1'b1),
                .clocks_ready(clocks_ready[output_index]), .ce_cpu(ce_cpu[output_index]),
                .ce_ula(ce_ula[output_index]), .ce_psg(ce_psg[output_index]),
                .ula_px_ce(px_ce), .ula_color(guest_color), .ula_x(x), .ula_y(y),
                .ula_hs_n(guest_hs_n), .ula_vs_n(guest_vs_n), .ula_blank(guest_blank),
                .loader_diag_active(loader_active), .loader_diag_code(loader_code),
                .clk_vga(clk_vga[output_index]), .rst_vga_n(rst_vga_n[output_index]),
                .vga_hs_n(hs_n[output_index]), .vga_vs_n(vs_n[output_index]),
                .vga_blank(blank[output_index]), .vga_r(rgb[output_index][17:12]),
                .vga_g(rgb[output_index][11:6]), .vga_b(rgb[output_index][5:0])
            );
            video_scan_check #(.OUTPUT_INDEX(output_index), .HEIGHT(HEIGHT)) check_vga (
                .clk(clk_vga[output_index]), .check_scan(check_scan[output_index]),
                .short_scan(short_scan), .done(scan_done[output_index]),
                .rgb(rgb[output_index]), .blank(blank[output_index]),
                .hs_n(hs_n[output_index]), .vs_n(vs_n[output_index])
            );
        end
    endgenerate

    video_enable_check #(.SYS_HZ(SYS_HZ)) check_rates (.clk(clk_sys), .done(rates_done));
    video_enable_check #(.SYS_HZ(80000000), .ALL_PROFILES(0)) check_alternate_rate (
        .clk(clk_80m), .done(alternate_rate_done)
    );

    task expect_idle;
        input integer monitor;
        begin
            if ({rgb[monitor], blank[monitor], hs_n[monitor], vs_n[monitor]} !== 21'd7)
                $fatal(1, "VGA %0d failed to idle with RGB zero during reset", monitor);
        end
    endtask

    initial begin
        #1;
        rst_n = 1'b0;
        rst_vga_n = 2'b00;
        #1;
        expect_idle(0);
        expect_idle(1);
        repeat (8) @(negedge clk_sys);
        rst_n = 1'b1;
        rst_vga_n = 2'b11;
        repeat (8) @(negedge clk_sys);
        if (clocks_ready !== 2'b11)
            $fatal(1, "Subsystem clocks did not qualify on startup");
        restart_raster = 1'b0;
        check_scan = 2'b11;
        wait (&scan_done && rates_done && alternate_rate_done);

        // Reset just the asynchronous VGA domain while it is showing color.
        wait (blank === 2'b00 && rgb[1] != 0);
        #1;
        check_scan = 2'b00;
        rst_vga_n[1] = 1'b0;
        #0.001;
        expect_idle(1);
        if (blank[0] !== 1'b0 || clocks_ready !== 2'b11)
            $fatal(1, "Independent VGA reset affected the other subsystem");
        @(negedge clk_sys);
        restart_raster = 1'b1;
        repeat (8) @(negedge clk_skew);
        rst_vga_n[1] = 1'b1;
        repeat (8) @(negedge clk_skew);
        expect_idle(1);
        @(negedge clk_sys);
        short_scan = 1'b1;
        check_scan = 2'b10;
        restart_raster = 1'b0;
        wait (scan_done[1]);
        wait (blank[1] === 1'b0 && rgb[1] != 0);
        #1;
        check_scan = 2'b00;
        rst_n = 1'b0;
        #0.001;
        expect_idle(0);
        expect_idle(1);
        if ({clocks_ready, ce_ula, ce_cpu, ce_psg} !== 8'd0)
            $fatal(1, "Fabric reset left an enable active");
        $display("PASS video_subsystem_tb");
        $finish;
    end

    initial begin
        #65000000;
        $fatal(1, "Video test timed out");
    end
endmodule

module video_enable_check #(
    parameter integer SYS_HZ = 85909080,
    parameter integer ALL_PROFILES = 1
) (
    input wire clk,
    output reg done = 1'b0
);
    localparam integer WINDOW = SYS_HZ / 200;
    localparam integer EXTRA = 2048;
    reg rst_n = 1'b1;
    reg [2:0] timing_id = 3'd0;
    reg psg_enable = 1'b1;
    wire ready, ula, cpu, psg;

    video_clock_enables #(.CLK_SYS_HZ(SYS_HZ)) dut (
        .clk_sys(clk), .rst_n(rst_n), .cfg_timing_id(timing_id), .cfg_psg_enable(psg_enable),
        .clocks_ready(ready), .ce_ula(ula), .ce_cpu(cpu), .ce_psg(psg)
    );

    task measure_profile;
        input [2:0] id;
        input integer base_hz;
        input integer samples;
        integer cycle;
        integer ula_count, cpu_count, psg_count;
        integer last_ula, gap_lo, gap_hi;
        integer expected_ticks;
        begin
            ula_count = 0;
            cpu_count = 0;
            psg_count = 0;
            last_ula = 0;
            gap_lo = SYS_HZ / (2 * base_hz);
            gap_hi = (SYS_HZ + 2 * base_hz - 1) / (2 * base_hz);
            for (cycle = 1; cycle <= samples + EXTRA; cycle = cycle + 1) begin
                if (cycle == samples + 1 || cycle == samples + EXTRA / 2) begin
                    @(negedge clk);
                    psg_enable = !psg_enable;
                end
                @(posedge clk);
                #0.001;
                if (ula === 1'b1) begin
                    ula_count = ula_count + 1;
                    if (cycle - last_ula < gap_lo || cycle - last_ula > gap_hi)
                        $fatal(1, "Timing %0d ULA interval was %0d clocks", id, cycle - last_ula);
                    last_ula = cycle;
                end else if (ula !== 1'b0) begin
                    $fatal(1, "Timing %0d ULA enable was unknown", id);
                end
                if (ready !== 1'b1 || cpu !== (ula && ula_count % 2 == 0) ||
                    psg !== (psg_enable && ula && ula_count % 4 == 0))
                    $fatal(1, "Timing %0d phase or PSG gate mismatch at cycle %0d", id, cycle);
                cpu_count = cpu_count + cpu;
                psg_count = psg_count + psg;
                if (cycle == samples) begin
                    expected_ticks = $floor(2.0 * base_hz * samples / SYS_HZ);
                    if (ula_count != expected_ticks || cpu_count != expected_ticks / 2 ||
                        psg_count != expected_ticks / 4)
                        $fatal(1, "Timing %0d rate mismatch (%0d/%0d/%0d ticks)",
                               id, cpu_count, ula_count, psg_count);
                    if (samples == WINDOW)
                        $display("timing_id %0d at sys %0d Hz: CPU %.1f Hz, ULA %.1f Hz, PSG %.1f Hz",
                                 id, SYS_HZ, 1.0 * cpu_count * SYS_HZ / samples,
                                 1.0 * ula_count * SYS_HZ / samples, 1.0 * psg_count * SYS_HZ / samples);
                end
            end
        end
    endtask

    task reset_profile;
        input [2:0] id;
        input integer base_hz;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            timing_id = id;
            #0.001;
            if ({ready, ula, cpu, psg} !== 4'd0)
                $fatal(1, "Timing %0d emitted a strobe in reset", id);
            @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
            if ({ready, ula, cpu, psg} !== 4'b1000)
                $fatal(1, "Timing %0d did not qualify with zero phase", id);
            measure_profile(id, base_hz, WINDOW);
        end
    endtask

    initial begin
        if (ALL_PROFILES) begin
            reset_profile(3'd0, 3500000);
            reset_profile(3'd1, 3546900);
            reset_profile(3'd2, 3546900);
            reset_profile(3'd3, 3575610);
            reset_profile(3'd4, 3575610);
            reset_profile(3'd5, 3500000);
            reset_profile(3'd6, 3500000);
            reset_profile(3'd7, 3500000);
            @(negedge clk);
            timing_id = 3'd4;
            #0.001;
            if ({ready, ula, cpu, psg} !== 4'd0)
                $fatal(1, "Live profile switch did not invalidate the old phase");
            @(negedge clk);
            measure_profile(3'd4, 3575610, WINDOW / 10);
        end else begin
            reset_profile(3'd4, 3575610);
        end
        done = 1'b1;
    end
endmodule

module video_scan_check #(
    parameter integer OUTPUT_INDEX = 0,
    parameter integer HEIGHT = 312
) (
    input wire clk,
    input wire check_scan,
    input wire short_scan,
    input wire [17:0] rgb,
    input wire blank,
    input wire hs_n,
    input wire vs_n,
    output reg done = 1'b0
);
    localparam integer FIRST_X = 24;
    localparam integer END_X = 376;
    localparam real LINE_NS = 32000.0;
    localparam real DOT_NS = LINE_NS / 448.0;
    localparam real EDGE_TOLERANCE_NS = 135.0;

    function [17:0] expected_rgb;
        input integer x, y, frame;
        integer cell_number, column;
        reg [7:0] code;
        reg [3:0] index_color;
        reg [5:0] level;
        begin
            index_color = (x + y + frame) % 16;
            if (frame > 0 && y < 12 && x < FIRST_X + 128) begin
                cell_number = (x - FIRST_X) / 16;
                column = (x - FIRST_X) % 16;
                code = (frame == 1) ? 8'ha6 : 8'h59;
                case (column)
                    0, 13, 14, 15: index_color = 4'h0;
                    1, 12: index_color = 4'hf;
                    default: begin
                        if (y == 4 || y == 11)
                            index_color = 4'hf;
                        else if ((code & (8'h80 >> cell_number)) != 0)
                            index_color = 4'he;
                        else
                            index_color = 4'h9;
                    end
                endcase
            end
            level = (index_color >= 8) ? 63 : 47;
            expected_rgb = {(index_color[1] ? level : 6'd0),
                            (index_color[2] ? level : 6'd0),
                            (index_color[0] ? level : 6'd0)};
        end
    endfunction

    integer line_number, guest_line, frame_number;
    integer run_x, next_x;
    integer vs_falls;
    reg previous_blank, previous_hs, previous_vs, visible_seen;
    reg [17:0] run_rgb;
    real run_start, active_start, first_hs, last_hs, last_vs;
    real frame_hz;

    task check_duration;
        input real actual_ns, ideal_ns, tolerance_ns;
        input [103:0] what;
        begin
            if (actual_ns < ideal_ns - tolerance_ns || actual_ns > ideal_ns + tolerance_ns)
                $fatal(1, "VGA %0d %0s at line %0d x=%0d: got %.3f ns, expected %.3f ns",
                       OUTPUT_INDEX, what, line_number, run_x, actual_ns, ideal_ns);
        end
    endtask

    // Score the pin waveform as runs of adjacent palette colors. The guest
    // pattern distinguishes neighboring pixels, lines and frames. A run's
    // duration is checked as well as its color, including the overlay runs.
    always @(posedge clk) begin
        #0.001;
        if (!check_scan) begin
            done = 1'b0;
            line_number = 0;
            vs_falls = 0;
            visible_seen = 1'b0;
            previous_blank = 1'b1;
            previous_hs = 1'b1;
            previous_vs = 1'b1;
            run_x = 0;
            first_hs = 0.0;
            last_hs = 0.0;
            last_vs = 0.0;
            frame_hz = 0.0;
        end else if (!done) begin
            guest_line = (line_number / 2) % HEIGHT;
            frame_number = line_number / (2 * HEIGHT);

            if ((^{rgb, blank, hs_n, vs_n}) === 1'bx || (blank && rgb != 0))
                $fatal(1, "VGA %0d unknown output or nonzero RGB during blank", OUTPUT_INDEX);

            if (!blank && previous_blank) begin
                if (visible_seen || guest_line < 4 || guest_line >= 292 || !hs_n)
                    $fatal(1, "VGA %0d unexpected active region on line %0d", OUTPUT_INDEX, line_number);
                visible_seen = 1'b1;
                active_start = $realtime;
                run_start = $realtime;
                run_x = FIRST_X;
                run_rgb = expected_rgb(run_x, guest_line, frame_number);
                if (rgb != run_rgb)
                    $fatal(1, "VGA %0d first RGB mismatch on line %0d", OUTPUT_INDEX, line_number);
            end else if (!previous_blank && (blank || rgb != run_rgb)) begin
                next_x = run_x + 1;
                while (next_x < END_X && expected_rgb(next_x, guest_line, frame_number) == run_rgb)
                    next_x = next_x + 1;
                check_duration($realtime - run_start, DOT_NS * (next_x - run_x), 60.0, "pixel run");
                if (blank) begin
                    if (next_x != END_X)
                        $fatal(1, "VGA %0d active region ended early at x=%0d", OUTPUT_INDEX, next_x);
                    check_duration($realtime - active_start, DOT_NS * (END_X - FIRST_X),
                                   250.0, "active width");
                end else begin
                    run_x = next_x;
                    run_rgb = expected_rgb(run_x, guest_line, frame_number);
                    run_start = $realtime;
                    if (run_x >= END_X || rgb != run_rgb)
                        $fatal(1, "VGA %0d RGB mismatch at line %0d x=%0d: got %h, expected %h",
                               OUTPUT_INDEX, line_number, run_x, rgb, run_rgb);
                end
            end

            if (vs_n != previous_vs) begin
                if (line_number % (2 * HEIGHT) != (vs_n ? 2 * 305 : 2 * 301))
                    $fatal(1, "VGA %0d extra or misplaced VS edge on line %0d", OUTPUT_INDEX, line_number);
                if (!vs_n) begin
                    if (vs_falls != 0) begin
                        check_duration($realtime - last_vs, 2 * HEIGHT * LINE_NS, 500.0, "frame period");
                        frame_hz = 1.0e9 / ($realtime - last_vs);
                    end
                    vs_falls = vs_falls + 1;
                    last_vs = $realtime;
                end
            end

            if (previous_hs && !hs_n) begin
                if (!blank || vs_n != (guest_line < 301 || guest_line >= 305) ||
                    visible_seen != (guest_line >= 4 && guest_line < 292))
                    $fatal(1, "VGA %0d bad sync or copy count on line %0d", OUTPUT_INDEX, line_number);
                if (line_number == 0)
                    first_hs = $realtime;
                else
                    check_duration($realtime - last_hs, LINE_NS, EDGE_TOLERANCE_NS, "line period");
                last_hs = $realtime;
                line_number = line_number + 1;
                visible_seen = 1'b0;
                if ((!short_scan && line_number == 4 * HEIGHT + 32) || (short_scan && line_number == 32)) begin
                    if (!short_scan && vs_falls != 2)
                        $fatal(1, "VGA %0d observed %0d VS pulses", OUTPUT_INDEX, vs_falls);
                    if (!short_scan)
                        $display("VGA %0d: %.3f kHz line, %.3f Hz frame (%0d doubled scanlines)",
                                 OUTPUT_INDEX, 1.0e6 * (line_number - 1) / (last_hs - first_hs),
                                 frame_hz, line_number);
                    done = 1'b1;
                end
            end else if (!previous_hs && hs_n) begin
                check_duration($realtime - last_hs, 32 * DOT_NS, 80.0, "HS low width");
            end

            previous_blank = blank;
            previous_hs = hs_n;
            previous_vs = vs_n;
        end
    end
endmodule
