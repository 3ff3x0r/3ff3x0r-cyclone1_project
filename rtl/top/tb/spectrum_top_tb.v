`timescale 1ps/1ps

module spectrum_top_tb;
    localparam integer SYS_PERIOD_PS = 11640;
    localparam integer SDRAM_LEAD_PS = 2909;
    localparam integer SLOT_BYTES = 16384;
    localparam [21:0] STAGING_BASE = 22'h030000;
    localparam [21:0] ACTIVE_BASE = 22'h020000;
    localparam [21:0] SIGNATURE_ADDR = 22'h000100;
    localparam [7:0] SIGNATURE = 8'h42;

    // 48K PAL, one ROM, no AY or disk, Kempston/Sinclair with both B mappings.
    localparam [40:0] EXPECTED_CFG = {
        4'd2, 2'd1, 3'd0, 3'd1, 16'h48a2, 4'b0001, 1'b0,
        2'd0, 2'd1, 2'd3, 2'd2
    };

    reg clk_sys = 1'b0;
    reg sdram_clk = 1'b0;
    reg rst_n = 1'b0;
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
    wire boot_commit_ready, boot_publish, boot_commit_done;
    wire [7:0] boot_error;
    wire mem_ready, clocks_ready, boot_overlay, cfg_valid, cpu_mem_deadline_miss;

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
        .vga_r(), .vga_g(), .vga_b(), .vga_hs_n(), .vga_vs_n(), .vga_blank(),
        .ps2_clk(1'b1), .ps2_data(1'b1), .joy1_n(6'h3f), .joy2_n(6'h3f),
        .audio_l(), .audio_r(), .sd_cs_n(), .sd_sck(), .sd_mosi(), .sd_miso(1'b1),
        .pending_profile_id(EXPECTED_CFG[40:37]), .pending_ram_size_id(EXPECTED_CFG[36:35]),
        .pending_timing_id(EXPECTED_CFG[34:32]), .pending_paging_id(EXPECTED_CFG[31:29]),
        .pending_rom_set_id(EXPECTED_CFG[28:13]), .pending_rom_valid_mask(EXPECTED_CFG[12:9]),
        .pending_psg_enable(EXPECTED_CFG[8]), .pending_disk_kind(EXPECTED_CFG[7:6]),
        .pending_input_map_id(EXPECTED_CFG[5:4]), .pending_joy1_b_map(EXPECTED_CFG[3:2]),
        .pending_joy2_b_map(EXPECTED_CFG[1:0]),
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
                14'h000a: guest_rom_byte = 8'h76; // HALT
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
            end

            #1;
            if (publishes == 0) begin
                if (active_cfg !== 41'd0 || {cfg_valid, boot_overlay, dut.sd_owner_boot} !== 3'b011 ||
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
    initial begin
        repeat (3) @(posedge clk_sys);
        #1;
        if ({boot_overlay, dut.sd_owner_boot, dut.cpu_reset_n, dut.guest_reset_n, cfg_valid} !== 5'b11000)
            fail("cold reset did not select the boot overlay and SD ownership");
        rst_n = 1'b1;
        wait (mem_ready && clocks_ready && boot_commit_ready && boot_fetch_seen);
        $display("PASS spectrum_top cold boot: boot overlay and SD boot ownership, CPU fetched boot ROM");

        for (offset = 0; offset < SLOT_BYTES; offset = offset + 1)
            loader_request(STAGING_BASE + {8'd0, offset[13:0]}, 1'b1, guest_rom_byte(offset[13:0]));
        // The loader initializes bank 5 and the other screen mirror before guest video uses them.
        for (offset = 0; offset < SLOT_BYTES; offset = offset + 1)
            loader_request(22'h014000 + {8'd0, offset[13:0]}, 1'b1, 8'd0);
        for (offset = 0; offset < 6912; offset = offset + 1)
            loader_request(22'h01c000 + {8'd0, offset[13:0]}, 1'b1, 8'd0);
        loader_request(SIGNATURE_ADDR, 1'b1, 8'd0);
        loader_request(SIGNATURE_ADDR + 22'd1, 1'b1, 8'd0);
        wait (dut.mem_idle);

        @(negedge clk_sys);
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
        $display("PASS spectrum_top commit: atomic configuration publish, overlay drop and guest release");

        wait (signature_written);
        check_loader_read(SIGNATURE_ADDR, SIGNATURE);
        check_loader_read(SIGNATURE_ADDR + 22'd1, SIGNATURE + 8'd1);
        $display("PASS spectrum_top guest execution: first fetch 020000, RAM signature 42 43");

        for (offset = 0; offset < SLOT_BYTES; offset = offset + 1)
            check_loader_read(ACTIVE_BASE + {8'd0, offset[13:0]}, guest_rom_byte(offset[13:0]));
        @(negedge clk_sys);
        $display("PASS spectrum_top ROM promotion: 16384 bytes from 030000-033fff to 020000-023fff");
        $display("PASS spectrum_top cpu_mem_deadline_miss=%b", cpu_mem_deadline_miss);
        $finish;
    end

    initial begin
        #(64'd1500000 * SYS_PERIOD_PS);
        fail("timed out waiting for boot, promotion or guest execution");
    end
endmodule
