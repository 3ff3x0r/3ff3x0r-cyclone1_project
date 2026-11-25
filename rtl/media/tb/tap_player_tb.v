`timescale 1ns/1ps

module tap_player_tb;
    localparam integer HEADER_SIZE = 19;
    localparam integer DATA_SIZE = 259;
    localparam integer IMAGE_SIZE = 2 + HEADER_SIZE + 2 + DATA_SIZE;
    localparam [21:0] IMAGE_BASE = 22'h100000 - IMAGE_SIZE;

    reg clk_sys = 0;
    always #5 clk_sys = !clk_sys;

    reg rst_n = 0, guest_reset_n = 0, boot_overlay = 1, media_quiesce = 1;
    reg tap_mount_update = 0, tap_mounted = 1;
    reg [21:0] tap_base = IMAGE_BASE;
    reg [31:0] tap_length = IMAGE_SIZE;
    reg tap_play_toggle = 0, tap_rewind = 0;
    reg ce_enable = 0, sparse_ce = 1;
    reg [1:0] ce_phase = 0;
    wire ce_cpu = ce_enable && (!sparse_ce || ce_phase == 2'd0);
    always @(negedge clk_sys)
        if (sparse_ce)
            ce_phase <= ce_phase + 2'd1;

    wire tap_rd_req, tap_playing, tap_ear_valid, tap_ear_bit, tap_idle;
    wire [31:0] tap_rd_offset;

    reg accept_enabled = 1, hold_response = 0;
    reg server_pending = 0;
    reg [3:0] delay_left = 0;
    reg [7:0] response_byte;
    reg [7:0] image [0:IMAGE_SIZE-1];
    integer image_limit = IMAGE_SIZE;
    integer tstates = 0;
    wire tap_rd_accept = accept_enabled && !server_pending;
    wire tap_rd_valid = server_pending && !hold_response && (delay_left == 4'd0);

    tap_player dut (
        .clk_sys(clk_sys), .rst_n(rst_n), .guest_reset_n(guest_reset_n),
        .boot_overlay(boot_overlay), .media_quiesce(media_quiesce),
        .ce_cpu(ce_cpu), .cfg_timing_id(3'd1),
        .tap_mount_update(tap_mount_update), .tap_mounted(tap_mounted),
        .tap_base(tap_base), .tap_length(tap_length),
        .tap_rd_req(tap_rd_req), .tap_rd_offset(tap_rd_offset),
        .tap_rd_accept(tap_rd_accept), .tap_rd_valid(tap_rd_valid),
        .tap_rd_data(response_byte), .tap_play_toggle(tap_play_toggle),
        .tap_rewind(tap_rewind), .tap_playing(tap_playing),
        .tap_ear_valid(tap_ear_valid), .tap_ear_bit(tap_ear_bit), .tap_idle(tap_idle)
    );

    // Model a staged byte adapter with varying response latency and
    // deliberately prolonged transactions for the transport tests.
    always @(posedge clk_sys) begin
        if (ce_cpu)
            tstates <= tstates + 1;
        if (rst_n && tap_rd_req) begin
            if (server_pending || media_quiesce || boot_overlay || !guest_reset_n)
                $fatal(1, "Request issued during a blocked transaction");
            if (tap_rd_offset >= image_limit)
                $fatal(1, "Read past file end at offset %0d", tap_rd_offset);
        end
        if (tap_rd_req && tap_rd_accept) begin
            server_pending <= 1'b1;
            response_byte <= image[tap_rd_offset];
            delay_left <= {1'b0, tap_rd_offset[2:0]} + 4'd1;
        end else if (tap_rd_valid) begin
            server_pending <= 1'b0;
        end else if (server_pending && (delay_left != 4'd0)) begin
            delay_left <= delay_left - 4'd1;
        end
    end

    task toggle_play;
        begin
            @(negedge clk_sys);
            tap_play_toggle = 1;
            @(negedge clk_sys);
            tap_play_toggle = 0;
        end
    endtask

    task rewind_and_toggle;
        begin
            @(negedge clk_sys);
            tap_rewind = 1;
            tap_play_toggle = 1;
            @(negedge clk_sys);
            tap_rewind = 0;
            tap_play_toggle = 0;
        end
    endtask

    task publish_mount;
        begin
            @(negedge clk_sys);
            tap_mount_update = 1;
            @(negedge clk_sys);
            tap_mount_update = 0;
        end
    endtask

    task expect_quiet;
        begin
            if (tap_playing !== 1'b0 || tap_ear_valid !== 1'b0 ||
                tap_rd_req !== 1'b0 || tap_idle !== 1'b1)
                $fatal(1, "Expected stopped and drained transport");
        end
    endtask

    task expect_offer;
        input [31:0] offset;
        integer cycles;
        begin
            cycles = 0;
            while (!tap_rd_req && cycles < 100) begin
                @(negedge clk_sys);
                cycles = cycles + 1;
            end
            if (tap_rd_req !== 1'b1 || tap_rd_offset !== offset || tap_idle !== 1'b0)
                $fatal(1, "Expected a pending request for offset %0d", offset);
        end
    endtask

    integer edge_tick;
    reg edge_level;

    task expect_pulse;
        input integer width;
        begin
            @(tap_ear_bit or negedge tap_ear_valid);
            #1;
            if (tap_ear_valid !== 1'b1 || tap_ear_bit !== !edge_level ||
                tstates - edge_tick != width)
                $fatal(1, "Expected %0d T-states to the next EAR edge, got %0d (valid %b)",
                       width, tstates - edge_tick, tap_ear_valid);
            if (!ce_cpu)
                $fatal(1, "EAR edge outside a CPU enable");
            edge_tick = tstates;
            edge_level = tap_ear_bit;
        end
    endtask

    // Independent counts from the TZX specification's standard-speed
    // block (IDs 10/11), with the payload taken from the fixture.
    // https://www.worldofspectrum.net/TZXformat.html
    task expect_block_data;
        input integer start;
        input integer count;
        integer byte_number, bit_number, width;
        begin
            expect_pulse(667);
            expect_pulse(735);
            for (byte_number = start; byte_number < start + count; byte_number = byte_number + 1)
                for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                    width = image[byte_number][bit_number] ? 1710 : 855;
                    expect_pulse(width);
                    expect_pulse(width);
                end
        end
    endtask

    integer i, partial_ticks;
    reg pause_level;
    reg [7:0] checksum;
    initial begin
        image[0]  = 8'd19;
        image[1]  = 8'd0;
        image[2]  = 8'h00; // header flag
        image[3]  = 8'h03; // CODE
        image[4]  = "T";
        image[5]  = "A";
        image[6]  = "P";
        image[7]  = "T";
        image[8]  = "E";
        image[9]  = "S";
        image[10] = "T";
        image[11] = " ";
        image[12] = " ";
        image[13] = " ";
        image[14] = 8'h01; // 257 data bytes
        image[15] = 8'h01;
        image[16] = 8'h00; // load at 8000h
        image[17] = 8'h80;
        image[18] = 8'h00;
        image[19] = 8'h80;
        checksum = 0;
        for (i = 2; i < 20; i = i + 1)
            checksum = checksum ^ image[i];
        image[20] = checksum;
        image[21] = 8'h03; // 259 bytes including flag and checksum
        image[22] = 8'h01;
        image[23] = 8'hff; // data flag
        checksum = 8'hff;
        for (i = 24; i < IMAGE_SIZE-1; i = i + 1) begin
            image[i] = i[7:0] ^ 8'ha5;
            checksum = checksum ^ image[i];
        end
        image[IMAGE_SIZE-1] = checksum;

        repeat (4) @(negedge clk_sys);
        rst_n = 1;
        publish_mount;
        guest_reset_n = 1;
        media_quiesce = 0;
        toggle_play;
        expect_quiet; // boot overlay ignores F9
        boot_overlay = 0;
        // Inputs can change after publication without replacing the mount.
        tap_length = 0;
        tap_mounted = 0;
        accept_enabled = 0;
        hold_response = 1;
        toggle_play;
        expect_offer(0);
        if (!tap_playing || tap_ear_valid)
            $fatal(1, "EAR became valid before prefetch");
        toggle_play;
        repeat (6) begin
            expect_offer(0);
            if (tap_playing || tap_ear_valid)
                $fatal(1, "Pause failed with a request awaiting acceptance");
            @(negedge clk_sys);
        end
        accept_enabled = 1;
        @(negedge clk_sys);
        if (!server_pending || tap_idle)
            $fatal(1, "Expected an accepted read while paused");
        media_quiesce = 1;
        rewind_and_toggle;
        repeat (8) @(negedge clk_sys);
        if (tap_idle || tap_rd_req || tap_ear_valid || tap_playing)
            $fatal(1, "Quiesce did not wait for the accepted read");
        hold_response = 0;
        @(negedge clk_sys);
        expect_quiet;
        media_quiesce = 0;
        expect_quiet;
        hold_response = 1;
        toggle_play;
        expect_offer(1); // the quiesce-edge rewind was ignored
        @(negedge clk_sys);
        rewind_and_toggle;
        if (tap_idle || tap_playing || tap_ear_valid || tap_rd_req)
            $fatal(1, "Rewind must beat toggle and retain the accepted read slot");
        toggle_play;
        repeat (8) @(negedge clk_sys);
        if (tap_idle || !tap_playing || tap_ear_valid || tap_rd_req)
            $fatal(1, "Replay must wait for the pre-rewind response");

        hold_response = 0;
        expect_offer(0);
        hold_response = 1;
        @(negedge clk_sys);
        guest_reset_n = 0;
        toggle_play;
        if (tap_idle || tap_playing || tap_ear_valid || tap_rd_req)
            $fatal(1, "Guest reset did not stop playback and preserve the read slot");
        guest_reset_n = 1;
        hold_response = 0;
        repeat (4) @(negedge clk_sys);
        expect_quiet;
        $display("PASS mount publication, boot gating, rewind priority, quiesce and guest-reset drain");

        ce_enable = 1;
        toggle_play;
        expect_offer(0);
        @(posedge tap_ear_valid);
        #1;
        edge_tick = tstates;
        edge_level = tap_ear_bit;
        expect_pulse(2168);

        wait (tstates == edge_tick + 321);
        @(negedge clk_sys);
        partial_ticks = tstates - edge_tick;
        pause_level = tap_ear_bit;
        tap_play_toggle = 1;
        @(negedge clk_sys);
        tap_play_toggle = 0;
        repeat (240) @(negedge clk_sys);
        if (tap_ear_valid || tap_playing || tap_ear_bit !== pause_level)
            $fatal(1, "Pause did not hold the in-progress pilot pulse");
        ce_enable = 0;
        toggle_play;
        if (!tap_ear_valid || !tap_playing || tap_ear_bit !== pause_level)
            $fatal(1, "Resume did not restore the prior EAR level");
        edge_tick = tstates;
        ce_enable = 1;
        expect_pulse(2168 - partial_ticks);
        $display("PASS sparse ce_cpu timing and play/pause pulse phase");

        @(negedge clk_sys);
        sparse_ce = 0;
        for (i = 2; i < 8063; i = i + 1)
            expect_pulse(2168);
        expect_block_data(2, HEADER_SIZE);
        if (tap_ear_bit !== 1'b0)
            $fatal(1, "Inter-block silence must be low");
        expect_pulse(3546900);
        $display("PASS header pilot, sync, data and one-second 128K inter-block pause");

        for (i = 0; i < 3223; i = i + 1)
            expect_pulse(2168);
        expect_block_data(23, DATA_SIZE);
        if (tap_ear_bit !== 1'b0)
            $fatal(1, "Final silence must be low");
        @(tap_ear_bit or negedge tap_ear_valid);
        #1;
        if (tap_ear_valid || tap_ear_bit !== 1'b0 || tstates - edge_tick != 3546900)
            $fatal(1, "Unexpected EOF or final gap length");
        expect_quiet;
        toggle_play;
        expect_quiet;
        $display("PASS data pilot, sync, two pulses per MSB-first bit and EOF");

        // Even an identical descriptor update is a new mount at offset zero.
        @(negedge clk_sys);
        media_quiesce = 1;
        tap_mounted = 1;
        tap_length = IMAGE_SIZE;
        publish_mount;
        media_quiesce = 0;
        expect_quiet;
        toggle_play;
        expect_offer(0);
        @(posedge tap_ear_valid);
        @(negedge clk_sys);
        rewind_and_toggle;
        repeat (30) @(negedge clk_sys);
        expect_quiet;

        // A malformed block must stop before emitting a pilot or crossing
        // its mounted file bounds. The server keeps the same header bytes.
        media_quiesce = 1;
        tap_length = 3;
        image_limit = 3;
        publish_mount;
        media_quiesce = 0;
        toggle_play;
        repeat (50) begin
            @(negedge clk_sys);
            if (tap_ear_valid)
                $fatal(1, "A truncated block emitted pulses");
        end
        expect_quiet;

        media_quiesce = 1;
        tap_length = 32'hfff00010;
        publish_mount;
        media_quiesce = 0;
        toggle_play;
        expect_quiet;
        repeat (20) begin
            @(negedge clk_sys);
            expect_quiet;
        end
        $display("PASS same-descriptor remount, truncated TAP and wrapping mount bounds");
        $display("PASS tap_player_tb");
        $finish;
    end

    initial begin
        #400000000;
        $fatal(1, "TAP test timed out");
    end
endmodule
