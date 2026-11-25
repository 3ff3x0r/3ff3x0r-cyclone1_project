`timescale 1ps/1ps

module spectrum_top_tb;
    localparam integer SYS_PERIOD_PS = 11640;
    localparam integer SDRAM_LEAD_PS = 2909;
    localparam integer SLOT_BYTES = 16384;
    localparam [21:0] STAGING_BASE = 22'h030000;
    localparam [21:0] ACTIVE_BASE = 22'h020000;
    localparam [21:0] SIGNATURE_ADDR = 22'h000100;
    localparam [7:0] SIGNATURE = 8'h42;
    localparam [21:0] TAP_BASE = 22'h08ffff;
    localparam [40:0] BOOT_CFG = {6'd0, 3'd4, 32'd0};

    // 48K PAL, one ROM, no AY or disk, Kempston/Sinclair with both B mappings.
    localparam [40:0] EXPECTED_CFG = {
        4'd2, 2'd1, 3'd0, 3'd1, 16'h48a2, 4'b0001, 1'b0,
        2'd0, 2'd1, 2'd3, 2'd2
    };

    reg clk_sys = 1'b0;
    reg sdram_clk = 1'b0;
    reg rst_n = 1'b0;
    reg ps2_clk = 1'b1, ps2_data = 1'b1;
    always #(SYS_PERIOD_PS/2) clk_sys = !clk_sys;
    initial begin
        #(SYS_PERIOD_PS/2 - SDRAM_LEAD_PS);
        forever begin
            sdram_clk = !sdram_clk;
            #(SYS_PERIOD_PS/2);
        end
    end

    reg boot_commit_valid = 1'b0;
    reg boot_stage_ok = 1'b0;
    reg boot_ram_init_ok = 1'b0;
    reg pending_tap_mounted = 1'b0;
    reg [21:0] pending_tap_base = TAP_BASE;
    wire boot_commit_ready, boot_publish, boot_commit_done;
    wire [7:0] boot_error;
    wire mem_ready, clocks_ready, boot_overlay, cfg_valid, cpu_mem_deadline_miss;
    wire vga_vs_n, vga_blank;
    wire [5:0] vga_r, vga_g, vga_b;

    reg ext_ld_mem_req = 1'b0;
    reg ext_ld_mem_we = 1'b0;
    reg [21:0] ext_ld_mem_addr = 22'd0;
    reg [7:0] ext_ld_mem_wdata = 8'd0;
    wire ext_ld_mem_accept, ext_ld_mem_rvalid;
    wire [7:0] ext_ld_mem_rdata;

    wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n;
    wire [12:0] sdram_a;
    wire [1:0] sdram_ba, sdram_dqm;
    wire [15:0] sdram_dq;

    wire clk_cpu;
    cpu_clock_model #(.FABRIC_PERIOD_PS(SYS_PERIOD_PS)) cpu_clock (clk_cpu);
    spectrum_top dut (
        .clk_sys(clk_sys), .clk_cpu(clk_cpu), .rst_n(rst_n), .clk_vga(clk_sys), .rst_vga_n(rst_n),
        .sdram_cke(sdram_cke), .sdram_cs_n(sdram_cs_n), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n), .sdram_a(sdram_a),
        .sdram_ba(sdram_ba), .sdram_dqm(sdram_dqm), .sdram_dq(sdram_dq),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs_n(),
        .vga_vs_n(vga_vs_n), .vga_blank(vga_blank),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data), .joy1_n(6'h3f), .joy2_n(6'h3f),
        .audio_l(), .audio_r(), .sd_cs_n(), .sd_sck(), .sd_mosi(), .sd_miso(1'b1),
        .pending_profile_id(EXPECTED_CFG[40:37]), .pending_ram_size_id(EXPECTED_CFG[36:35]),
        .pending_timing_id(EXPECTED_CFG[34:32]), .pending_paging_id(EXPECTED_CFG[31:29]),
        .pending_rom_set_id(EXPECTED_CFG[28:13]), .pending_rom_valid_mask(EXPECTED_CFG[12:9]),
        .pending_psg_enable(EXPECTED_CFG[8]), .pending_disk_kind(EXPECTED_CFG[7:6]),
        .pending_input_map_id(EXPECTED_CFG[5:4]), .pending_joy1_b_map(EXPECTED_CFG[3:2]),
        .pending_joy2_b_map(EXPECTED_CFG[1:0]),
        .pending_tap_mounted(pending_tap_mounted), .pending_tap_base(pending_tap_base),
        .pending_tap_length(32'd4),
        .boot_commit_valid(boot_commit_valid), .boot_commit_ready(boot_commit_ready),
        .boot_stage_ok(boot_stage_ok), .boot_ram_init_ok(boot_ram_init_ok),
        .boot_publish(boot_publish), .boot_commit_done(boot_commit_done), .boot_error(boot_error),
        .boot_recovery(), .loader_diag_active(1'b0), .loader_diag_code(8'd0),
        .ext_ld_mem_req(ext_ld_mem_req), .ext_ld_mem_accept(ext_ld_mem_accept),
        .ext_ld_mem_addr(ext_ld_mem_addr), .ext_ld_mem_we(ext_ld_mem_we),
        .ext_ld_mem_wdata(ext_ld_mem_wdata), .ext_ld_mem_rvalid(ext_ld_mem_rvalid),
        .ext_ld_mem_rdata(ext_ld_mem_rdata), .mem_ready(mem_ready), .clocks_ready(clocks_ready),
        .boot_overlay(boot_overlay), .cfg_valid(cfg_valid),
        .cpu_mem_deadline_miss(cpu_mem_deadline_miss)
    );

    // The controller's 22-bit byte address always leaves U5 A10..A12 of
    // the row at zero. Model the lower 4 MiB with the same column and BA wiring.
    sdram_x16_model #(.ROW_BITS(10)) sdram (
        .rst_n(rst_n), .clk(sdram_clk), .cke(sdram_cke), .cs_n(sdram_cs_n),
        .ras_n(sdram_ras_n), .cas_n(sdram_cas_n), .we_n(sdram_we_n), .a(sdram_a),
        .ba(sdram_ba), .dqm(sdram_dqm), .dq(sdram_dq), .column_word_addr()
    );

    wire [40:0] active_cfg = {
        dut.cfg_profile_id, dut.cfg_ram_size_id, dut.cfg_timing_id, dut.cfg_paging_id,
        dut.cfg_rom_set_id, dut.cfg_rom_valid_mask, dut.cfg_psg_enable, dut.cfg_disk_kind,
        dut.cfg_input_map_id, dut.cfg_joy1_b_map, dut.cfg_joy2_b_map
    };

    function [7:0] guest_rom_byte;
        input [13:0] offset;
        begin
            case (offset)
                14'h0000: guest_rom_byte = 8'hf3; // DI
                14'h0001: guest_rom_byte = 8'h3e; // LD A,42h
                14'h0002: guest_rom_byte = SIGNATURE;
                14'h0003: guest_rom_byte = 8'h32; // LD (C100h),A
                14'h0004: guest_rom_byte = 8'h00;
                14'h0005: guest_rom_byte = 8'hc1;
                14'h0006: guest_rom_byte = 8'h3c; // INC A
                14'h0007: guest_rom_byte = 8'h32; // LD (C101h),A
                14'h0008: guest_rom_byte = 8'h01;
                14'h0009: guest_rom_byte = 8'hc1;
                14'h000a: guest_rom_byte = 8'h01; // LD BC,FFFEh
                14'h000b: guest_rom_byte = 8'hfe;
                14'h000c: guest_rom_byte = 8'hff;
                14'h000d: guest_rom_byte = 8'hed; // poll: IN A,(C)
                14'h000e: guest_rom_byte = 8'h78;
                14'h000f: guest_rom_byte = 8'hcb; // BIT 6,A
                14'h0010: guest_rom_byte = 8'h77;
                14'h0011: guest_rom_byte = 8'h20; // JR NZ,poll
                14'h0012: guest_rom_byte = 8'hfa;
                14'h0013: guest_rom_byte = 8'h32; // LD (C102h),A
                14'h0014: guest_rom_byte = 8'h02;
                14'h0015: guest_rom_byte = 8'hc1;
                14'h0016: guest_rom_byte = 8'h76; // HALT
                default: guest_rom_byte = offset[7:0] ^ {2'b01, offset[13:8]};
            endcase
        end
    endfunction

    task fail;
        input [8*96-1:0] reason;
        begin
            $display("FAIL spectrum_top at %0t: %0s", $time, reason);
            $stop;
        end
    endtask

    task loader_request;
        input [21:0] address;
        input write_enable;
        input [7:0] write_data;
        begin
            @(negedge clk_sys);
            ext_ld_mem_addr = address;
            ext_ld_mem_we = write_enable;
            ext_ld_mem_wdata = write_data;
            ext_ld_mem_req = 1'b1;
            @(posedge clk_sys);
            while (ext_ld_mem_accept !== 1'b1)
                @(posedge clk_sys);
            @(negedge clk_sys);
            ext_ld_mem_req = 1'b0;
            ext_ld_mem_we = 1'b0;
        end
    endtask

    task check_loader_read;
        input [21:0] address;
        input [7:0] expected;
        begin
            loader_request(address, 1'b0, 8'd0);
            @(posedge clk_sys);
            while (ext_ld_mem_rvalid !== 1'b1)
                @(posedge clk_sys);
            if (ext_ld_mem_rdata !== expected) begin
                $display("SDRAM byte %06h expected %02h, read %02h", address, expected, ext_ld_mem_rdata);
                fail("loader readback mismatch");
            end
        end
    endtask

    task ps2_bit;
        input value;
        begin
            @(negedge clk_sys);
            ps2_data = value;
            repeat (24) @(negedge clk_sys);
            ps2_clk = 1'b0;
            repeat (24) @(negedge clk_sys);
            ps2_clk = 1'b1;
            repeat (24) @(negedge clk_sys);
        end
    endtask

    task ps2_byte;
        input [7:0] scan;
        integer bit_number;
        begin
            ps2_bit(1'b0);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1)
                ps2_bit(scan[bit_number]);
            ps2_bit(~^scan);
            ps2_bit(1'b1);
        end
    endtask

    task press_key;
        input [7:0] scan;
        begin
            ps2_byte(scan);
            ps2_byte(8'hf0);
            ps2_byte(scan);
        end
    endtask

    function [7:0] tap_byte;
        input [1:0] file_offset;
        begin
            case (file_offset)
                2'd0: tap_byte = 8'h02;
                2'd1: tap_byte = 8'h00;
                default: tap_byte = 8'hff;
            endcase
        end
    endfunction

    integer tape_ticks = 0, tape_reads = 0, tape_replies = 0;
    reg ear_signature_written = 1'b0;
    reg tape_read_pending = 1'b0;
    reg [7:0] tape_expected;
    always @(posedge clk_sys) begin
        if (rst_n && dut.ce_cpu)
            tape_ticks <= tape_ticks + 1;
        if (rst_n && dut.tap_rd_req && dut.tap_rd_accept) begin
            if (boot_overlay || dut.media_quiesce || tape_read_pending ||
                dut.tap_rd_offset >= 32'd4 || dut.ld_mem_we ||
                dut.ld_mem_addr !== TAP_BASE + dut.tap_rd_offset[21:0])
                fail("TAP read did not use the published cache descriptor");
            tape_read_pending <= 1'b1;
            tape_expected <= tap_byte(dut.tap_rd_offset[1:0]);
            tape_reads <= tape_reads + 1;
        end
        if (rst_n && dut.tap_rd_valid) begin
            if (!tape_read_pending || dut.ld_mem_rdata !== tape_expected ||
                ext_ld_mem_rvalid || dut.promo_mem_rvalid)
                fail("TAP completion was corrupt, unsolicited or misrouted");
            tape_read_pending <= 1'b0;
            tape_replies <= tape_replies + 1;
        end
        if (rst_n && tape_read_pending && (ext_ld_mem_rvalid || dut.promo_mem_rvalid))
            fail("Another loader client received the pending TAP read response");
    end

    task check_tap_playback;
        integer pilot_start;
        begin
            fork
                press_key(8'h01); // F9
                begin
                    @(posedge clk_sys);
                    while (!(dut.tap_rd_req && dut.tap_rd_accept)) @(posedge clk_sys);
                    check_loader_read(ACTIVE_BASE, 8'hf3);
                end
                begin
                    @(posedge dut.tap_ear_valid);
                    #1;
                    if (dut.ear_bit !== 1'b1)
                        fail("Pilot did not begin high on EAR");
                    pilot_start = tape_ticks;
                    @(negedge dut.ear_bit);
                    #1;
                    if (!dut.tap_ear_valid || tape_ticks - pilot_start != 2168)
                        fail("First pilot pulse did not last 2168 nominal CPU ticks");
                end
            join
            wait (ear_signature_written);
            check_loader_read(SIGNATURE_ADDR + 22'd2, 8'hbf);
        end
    endtask

    task check_tap_quiesce;
        integer reads_before;
        begin
            press_key(8'h09); // F10, rewind and pause
            if (dut.tap_playing || !dut.tap_idle || dut.ear_bit !== 1'b1)
                fail("Rewind did not pause playback and return EAR to idle");
            reads_before = tape_reads;
            fork
                press_key(8'h01);
                begin
                    @(posedge clk_sys);
                    while (!(dut.tap_rd_req && dut.tap_rd_accept)) @(posedge clk_sys);
                    if (dut.tap_rd_offset !== 32'd0)
                        fail("Rewind did not restart at file offset zero");
                    // Inject the decoded F11 level immediately after acceptance
                    // so the real orchestrator must drain an in-flight read.
                    @(negedge clk_sys);
                    force dut.soft_reset_key = 1'b1;
                    @(posedge clk_sys);
                    #1;
                    if (!dut.media_quiesce || dut.tap_idle || dut.media_idle ||
                        !dut.guest_reset_n || dut.tap_rd_req)
                        fail("Quiesce did not hold guest reset until the TAP response");
                    @(negedge clk_sys);
                    release dut.soft_reset_key;
                    wait (dut.tap_rd_valid);
                    if (dut.tap_idle || !dut.media_quiesce || !dut.guest_reset_n)
                        fail("Guest reset advanced before consuming the TAP response");
                    @(posedge clk_sys);
                    #1;
                    if (!dut.tap_idle || !dut.media_idle || tape_reads != reads_before + 1 ||
                        tape_replies != tape_reads)
                        fail("TAP read did not drain exactly once during quiesce");
                    wait (!dut.guest_reset_n);
                    wait (dut.guest_reset_n);
                end
            join
            if (dut.tap_playing || !dut.tap_idle || dut.ear_bit !== 1'b1)
                fail("Playback was not paused after warm reset");
        end
    endtask

    reg bringup;
    integer smoke_writes = 0, smoke_border_writes = 0, smoke_loop_fetches = 0;
    reg saw_cyan = 1'b0, saw_white = 1'b0, saw_blue = 1'b0;
    time last_vsync = 0, vga_frame_clocks = 0;

    always @(negedge vga_vs_n) begin
        if (rst_n && bringup) begin
            if (last_vsync != 0)
                vga_frame_clocks = ($time - last_vsync) / SYS_PERIOD_PS;
            last_vsync = $time;
        end
    end

    always @(posedge clk_sys) begin
        if (rst_n && bringup) begin
            if (dut.boot_bus_req && dut.boot_bus_ready) begin
                if (dut.boot_bus_io && dut.boot_bus_we) begin
                    if (smoke_border_writes != 0 || dut.boot_bus_addr[7:0] !== 8'hfe ||
                        dut.boot_bus_wdata !== 8'h05)
                        fail("smoke ROM did not write cyan to FE exactly once");
                    smoke_border_writes <= smoke_border_writes + 1;
                end else if (!dut.boot_bus_io && !dut.boot_bus_we &&
                             !dut.core.m1_n && dut.boot_bus_addr == 16'h001f) begin
                    if (smoke_writes != 6912 || dut.boot_bus_rdata !== 8'h18)
                        fail("smoke ROM reached JR before completing the screen");
                    smoke_loop_fetches <= smoke_loop_fetches + 1;
                end
            end
            if (dut.boot_mem_req && dut.boot_mem_accept && dut.boot_mem_we) begin
                if (smoke_writes >= 6912 || dut.boot_mem_addr !== 22'h014000 + smoke_writes[21:0] ||
                    dut.boot_mem_wdata !== (smoke_writes < 6144 ? 8'haa : 8'h4f))
                    fail("smoke ROM write did not match the bank 5 address or pattern");
                smoke_writes <= smoke_writes + 1;
            end
            if (smoke_loop_fetches >= 2 && !vga_blank) begin
                case ({vga_r, vga_g, vga_b})
                    {6'd0, 6'd47, 6'd47}: saw_cyan <= 1'b1;
                    {6'd63, 6'd63, 6'd63}: saw_white <= 1'b1;
                    {6'd0, 6'd0, 6'd63}: saw_blue <= 1'b1;
                    default: begin end
                endcase
            end
        end
    end

    task check_bringup;
        integer pixel;
        begin
            wait (smoke_loop_fetches >= 2);
            if (smoke_border_writes != 1)
                fail("smoke ROM did not set the boot border");
            check_loader_read(22'h014000, 8'haa);
            check_loader_read(22'h0157ff, 8'haa);
            check_loader_read(22'h015800, 8'h4f);
            check_loader_read(22'h015aff, 8'h4f);

            @(posedge clk_sys);
            while (!(dut.ula_px_ce && dut.ula_y == 9'd32 && dut.ula_x == 10'd52))
                @(posedge clk_sys);
            for (pixel = 0; pixel < 8; pixel = pixel + 1) begin
                if (dut.ula_x !== 10'd52 + pixel[9:0] ||
                    dut.ula_color !== (pixel[0] ? 4'h9 : 4'hf))
                    fail("first TK90X picture byte did not render alternating white and blue");
                @(posedge clk_sys);
                while (!dut.ula_px_ce) @(posedge clk_sys);
            end
            wait (saw_cyan && saw_white && saw_blue && vga_frame_clocks != 0);
            // TK90X PAL-M: 456 pixels by 262 lines at 7.15122 MHz.
            if (vga_frame_clocks < 1435239 || vga_frame_clocks > 1435244)
                fail("VGA vertical sync period did not match the 59.86 Hz boot raster");
            $display("PASS spectrum_top bring-up: %0d screen writes, cyan border, white/blue stripes, JR loop, VGA frame %0d fabric clocks",
                     smoke_writes, vga_frame_clocks);
        end
    endtask

    integer publishes = 0;
    integer completions = 0;
    reg first_fetch_seen = 1'b0;
    reg signature_written = 1'b0;
    reg boot_fetch_seen = 1'b0;
    always @(posedge clk_sys) begin
        if (rst_n) begin
            if (cpu_mem_deadline_miss !== 1'b0)
                fail("CPU memory deadline missed");
            if (dut.boot_bus_req && dut.boot_bus_ready &&
                !dut.boot_bus_io && !dut.boot_bus_we && dut.boot_bus_addr == 16'h0000)
                boot_fetch_seen <= 1'b1;

            if (boot_publish) begin
                if (publishes != 0 || {boot_overlay, dut.sd_owner_boot, cfg_valid} !== 3'b110 ||
                    {dut.cpu_reset_n, dut.guest_reset_n, dut.mem_idle} !== 3'b001)
                    fail("publish requires drained memory and both resets while the loader owns the system");
                publishes = publishes + 1;
            end

            if (dut.promo_active && {dut.cpu_reset_n, dut.guest_reset_n} !== 2'b00)
                fail("CPU or guest peripherals escaped reset during promotion");
            if (!boot_overlay && dut.core_mem_req && dut.core_mem_accept) begin
                if (!first_fetch_seen) begin
                    if ({dut.guest_reset_n, dut.cpu_reset_n, dut.core_mem_we, dut.core.m1_n} !== 4'b1100 ||
                        dut.core_mem_addr !== ACTIVE_BASE)
                        fail("first guest bus access was not an opcode fetch from active ROM slot 0");
                    first_fetch_seen <= 1'b1;
                end
                if (dut.core_mem_we && dut.core_mem_addr == SIGNATURE_ADDR + 22'd1)
                    signature_written <= 1'b1;
                if (dut.core_mem_we && dut.core_mem_addr == SIGNATURE_ADDR + 22'd2)
                    ear_signature_written <= 1'b1;
            end

            #1;
            if (publishes == 0) begin
                if (active_cfg !== BOOT_CFG || {cfg_valid, boot_overlay, dut.sd_owner_boot} !== 3'b011 ||
                    dut.guest_reset_n !== 1'b0)
                    fail("boot ownership or configuration changed before publish");
            end else if (active_cfg !== EXPECTED_CFG || {cfg_valid, boot_overlay, dut.sd_owner_boot} !== 3'b100) begin
                fail("configuration, overlay and SD ownership did not change atomically");
            end
            if (boot_commit_done) begin
                if (publishes != 1 || completions != 0 || boot_error !== 8'd0 ||
                    {dut.cpu_reset_n, dut.guest_reset_n} !== 2'b00)
                    fail("commit did not complete successfully with CPU and guest held in reset");
                completions = completions + 1;
            end
        end
    end

    integer offset;
    initial begin : exercise_top
        bringup = $test$plusargs("bringup");
        repeat (3) @(posedge clk_sys);
        #1;
        if ({boot_overlay, dut.sd_owner_boot, dut.cpu_reset_n, dut.guest_reset_n, cfg_valid} !== 5'b11000)
            fail("cold reset did not select the boot overlay and SD ownership");
        rst_n = 1'b1;
        wait (mem_ready && clocks_ready && boot_commit_ready && boot_fetch_seen);
        $display("PASS spectrum_top cold boot: boot overlay and SD boot ownership, CPU fetched boot ROM");

        if (bringup) begin
            check_bringup;
            $finish;
            disable exercise_top;
        end

        for (offset = 0; offset < SLOT_BYTES; offset = offset + 1)
            loader_request(STAGING_BASE + {8'd0, offset[13:0]}, 1'b1, guest_rom_byte(offset[13:0]));
        // The loader initializes bank 5 and the other screen mirror before guest video uses them.
        for (offset = 0; offset < SLOT_BYTES; offset = offset + 1)
            loader_request(22'h014000 + {8'd0, offset[13:0]}, 1'b1, 8'd0);
        for (offset = 0; offset < 6912; offset = offset + 1)
            loader_request(22'h01c000 + {8'd0, offset[13:0]}, 1'b1, 8'd0);
        loader_request(SIGNATURE_ADDR, 1'b1, 8'd0);
        loader_request(SIGNATURE_ADDR + 22'd1, 1'b1, 8'd0);
        loader_request(SIGNATURE_ADDR + 22'd2, 1'b1, 8'd0);
        for (offset = 0; offset < 4; offset = offset + 1)
            loader_request(TAP_BASE + offset[21:0], 1'b1, tap_byte(offset[1:0]));
        wait (dut.mem_idle);

        @(negedge clk_sys);
        pending_tap_mounted = 1'b1;
        boot_stage_ok = 1'b1;
        boot_ram_init_ok = 1'b1;
        boot_commit_valid = 1'b1;
        @(posedge clk_sys);
        while (boot_commit_ready !== 1'b1)
            @(posedge clk_sys);
        @(negedge clk_sys);
        boot_commit_valid = 1'b0;
        wait (completions == 1);
        wait (dut.cpu_reset_n && dut.guest_reset_n);
        @(negedge clk_sys);
        pending_tap_mounted = 1'b0;
        pending_tap_base = 22'd0;
        if (dut.tap_playing || !dut.tap_idle || dut.ear_bit !== 1'b1)
            fail("Published tape did not start paused");
        $display("PASS spectrum_top commit: atomic configuration publish, overlay drop and guest release");

        wait (signature_written);
        check_loader_read(SIGNATURE_ADDR, SIGNATURE);
        check_loader_read(SIGNATURE_ADDR + 22'd1, SIGNATURE + 8'd1);
        $display("PASS spectrum_top guest execution: first fetch 020000, RAM signature 42 43");

        for (offset = 0; offset < SLOT_BYTES; offset = offset + 1)
            check_loader_read(ACTIVE_BASE + {8'd0, offset[13:0]}, guest_rom_byte(offset[13:0]));
        @(negedge clk_sys);
        $display("PASS spectrum_top ROM promotion: 16384 bytes from 030000-033fff to 020000-023fff");
        check_tap_playback;
        $display("PASS spectrum_top TAP: published mount, SDRAM/loader response routing, F9, 2168-tick pilot, CPU FE read");
        check_tap_quiesce;
        $display("PASS spectrum_top TAP: F10 rewind and media_quiesce drain of an accepted read before guest reset");
        $display("PASS spectrum_top cpu_mem_deadline_miss=%b", cpu_mem_deadline_miss);
        $finish;
    end

    initial begin
        if ($test$plusargs("bringup")) begin
            #(64'd6000000 * SYS_PERIOD_PS);
            fail("timed out waiting for the smoke ROM screen and VGA raster");
        end
        #(64'd1500000 * SYS_PERIOD_PS);
        fail("timed out waiting for boot, promotion or guest execution");
    end
endmodule
