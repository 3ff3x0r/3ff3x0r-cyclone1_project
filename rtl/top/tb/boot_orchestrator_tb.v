`timescale 1ns/1ps

module boot_orchestrator_tb;
    reg clk_sys = 1'b0;
    always #5 clk_sys = ~clk_sys;

    reg        rst_n = 1'b0;
    reg        clocks_ready = 1'b0;
    reg        mem_ready = 1'b0;
    reg        mem_idle = 1'b1;
    reg        cpu_quiesced = 1'b1;
    reg        media_idle = 1'b1;
    reg        soft_reset_key = 1'b0;
    reg        recovery_key = 1'b0;

    reg [3:0]  pending_profile_id = 4'd0;
    reg [1:0]  pending_ram_size_id = 2'd0;
    reg [2:0]  pending_timing_id = 3'd0;
    reg [2:0]  pending_paging_id = 3'd0;
    reg [15:0] pending_rom_set_id = 16'd0;
    reg [3:0]  pending_rom_valid_mask = 4'd0;
    reg        pending_psg_enable = 1'b0;
    reg [1:0]  pending_disk_kind = 2'd0;
    reg [1:0]  pending_input_map_id = 2'd0;
    reg [1:0]  pending_joy1_b_map = 2'd0;
    reg [1:0]  pending_joy2_b_map = 2'd0;

    reg        boot_commit_valid = 1'b0;
    wire       boot_commit_ready;
    reg        boot_stage_ok = 1'b0;
    reg        boot_ram_init_ok = 1'b0;
    wire       boot_publish;
    wire       boot_commit_done;
    wire [7:0] boot_error;
    wire       boot_recovery;

    wire        cfg_valid;
    wire [3:0]  cfg_profile_id;
    wire [1:0]  cfg_ram_size_id;
    wire [2:0]  cfg_timing_id;
    wire [2:0]  cfg_paging_id;
    wire [15:0] cfg_rom_set_id;
    wire [3:0]  cfg_rom_valid_mask;
    wire        cfg_psg_enable;
    wire [1:0]  cfg_disk_kind;
    wire [1:0]  cfg_input_map_id;
    wire [1:0]  cfg_joy1_b_map;
    wire [1:0]  cfg_joy2_b_map;

    wire        boot_overlay;
    wire        sd_owner_boot;
    wire        cpu_reset_n;
    wire        guest_reset_n;
    wire        cpu_quiesce;
    wire        media_quiesce;

    wire        promo_active;
    wire        promo_mem_req;
    reg         promo_mem_accept = 1'b0;
    wire [21:0] promo_mem_addr;
    wire        promo_mem_we;
    wire [7:0]  promo_mem_wdata;
    reg         promo_mem_rvalid = 1'b0;
    reg  [7:0]  promo_mem_rdata = 8'd0;

    boot_orchestrator #(.ROM_SLOT_BYTES(15'd16)) dut (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .clocks_ready(clocks_ready), .mem_ready(mem_ready), .mem_idle(mem_idle),
        .cpu_quiesced(cpu_quiesced), .media_idle(media_idle),
        .soft_reset_key(soft_reset_key), .recovery_key(recovery_key),
        .pending_profile_id(pending_profile_id), .pending_ram_size_id(pending_ram_size_id),
        .pending_timing_id(pending_timing_id), .pending_paging_id(pending_paging_id),
        .pending_rom_set_id(pending_rom_set_id), .pending_rom_valid_mask(pending_rom_valid_mask),
        .pending_psg_enable(pending_psg_enable), .pending_disk_kind(pending_disk_kind),
        .pending_input_map_id(pending_input_map_id), .pending_joy1_b_map(pending_joy1_b_map),
        .pending_joy2_b_map(pending_joy2_b_map),
        .boot_commit_valid(boot_commit_valid), .boot_commit_ready(boot_commit_ready),
        .boot_stage_ok(boot_stage_ok), .boot_ram_init_ok(boot_ram_init_ok),
        .boot_publish(boot_publish), .boot_commit_done(boot_commit_done),
        .boot_error(boot_error), .boot_recovery(boot_recovery),
        .cfg_valid(cfg_valid), .cfg_profile_id(cfg_profile_id),
        .cfg_ram_size_id(cfg_ram_size_id), .cfg_timing_id(cfg_timing_id),
        .cfg_paging_id(cfg_paging_id), .cfg_rom_set_id(cfg_rom_set_id),
        .cfg_rom_valid_mask(cfg_rom_valid_mask), .cfg_psg_enable(cfg_psg_enable),
        .cfg_disk_kind(cfg_disk_kind), .cfg_input_map_id(cfg_input_map_id),
        .cfg_joy1_b_map(cfg_joy1_b_map), .cfg_joy2_b_map(cfg_joy2_b_map),
        .boot_overlay(boot_overlay), .sd_owner_boot(sd_owner_boot),
        .cpu_reset_n(cpu_reset_n), .guest_reset_n(guest_reset_n),
        .cpu_quiesce(cpu_quiesce), .media_quiesce(media_quiesce),
        .promo_active(promo_active), .promo_mem_req(promo_mem_req),
        .promo_mem_accept(promo_mem_accept), .promo_mem_addr(promo_mem_addr),
        .promo_mem_we(promo_mem_we), .promo_mem_wdata(promo_mem_wdata),
        .promo_mem_rvalid(promo_mem_rvalid), .promo_mem_rdata(promo_mem_rdata)
    );

    // Two 64 KiB ROM regions at their fabric addresses.
    reg [7:0] active_rom [0:65535];
    reg [7:0] stage_rom  [0:65535];
    integer i;
    always @* promo_mem_accept = promo_mem_req;
    always @(posedge clk_sys) begin
        promo_mem_rvalid <= 1'b0;
        if (promo_mem_req && promo_mem_accept) begin
            if (promo_mem_we) begin
                if (promo_mem_addr[21:16] !== 6'h02) begin
                    $display("FAIL active ROM write outside 020000-02ffff: %06h", promo_mem_addr);
                    $stop;
                end
                active_rom[promo_mem_addr[15:0]] <= promo_mem_wdata;
            end else begin
                if (promo_mem_addr[21:16] !== 6'h03) begin
                    $display("FAIL staging ROM read outside 030000-03ffff: %06h", promo_mem_addr);
                    $stop;
                end
                promo_mem_rvalid <= 1'b1;
                promo_mem_rdata  <= stage_rom[promo_mem_addr[15:0]];
            end
        end
    end

    task tick;
        begin
            @(posedge clk_sys);
            #1;
        end
    endtask

    initial begin
        for (i = 0; i < 65536; i = i + 1) begin
            active_rom[i] = 8'h00;
            stage_rom[i]  = (i[7:0] ^ 8'ha5);
        end

        // 1. Reset state
        tick; tick;
        if (!boot_overlay || !sd_owner_boot || cpu_reset_n || guest_reset_n || cfg_valid) begin
            $display("FAIL reset state");
            $finish;
        end

        // 2. Release fabric reset, wait for clocks_ready
        rst_n = 1'b1;
        tick;
        if (cpu_reset_n) begin
            $display("FAIL cpu released before clocks_ready");
            $finish;
        end
        clocks_ready = 1'b1;
        mem_ready = 1'b1;
        tick; tick;
        if (!cpu_reset_n || guest_reset_n || !boot_overlay) begin
            $display("FAIL boot run entry");
            $finish;
        end

        // 3. Reject invalid profile (48K with joy2_b_map=3)
        pending_profile_id = 4'd2;
        pending_ram_size_id = 2'd1;
        pending_timing_id = 3'd0;
        pending_paging_id = 3'd1;
        pending_rom_set_id = 16'h0048;
        pending_rom_valid_mask = 4'b0001;
        pending_joy2_b_map = 2'd3;
        boot_stage_ok = 1'b1;
        boot_ram_init_ok = 1'b1;
        boot_commit_valid = 1'b1;
        tick;
        if (!boot_commit_done || boot_error != 8'd3 || cfg_valid) begin
            $display("FAIL invalid profile rejection: done=%b err=%d", boot_commit_done, boot_error);
            $finish;
        end
        boot_commit_valid = 1'b0;
        tick;

        // 4. Valid 48K commit + ROM promotion
        pending_joy2_b_map = 2'd0;
        boot_commit_valid = 1'b1;
        tick;
        boot_commit_valid = 1'b0;

        for (i = 0; i < 200 && !boot_commit_done; i = i + 1)
            tick;

        if (!boot_commit_done || boot_error != 8'd0 || !cfg_valid || boot_overlay || sd_owner_boot) begin
            $display("FAIL valid commit: done=%b err=%d valid=%b ovl=%b",
                     boot_commit_done, boot_error, cfg_valid, boot_overlay);
            $finish;
        end
        tick;
        if (!guest_reset_n || !cpu_reset_n) begin
            $display("FAIL guest release");
            $finish;
        end
        for (i = 0; i < 16; i = i + 1) begin
            if (active_rom[i] !== stage_rom[i]) begin
                $display("FAIL ROM promotion mismatch at %0d: got %h exp %h",
                         i, active_rom[i], stage_rom[i]);
                $finish;
            end
        end

        // 5. F11 soft guest reset
        soft_reset_key = 1'b1;
        tick; tick;
        if (guest_reset_n || cpu_reset_n || boot_overlay) begin
            $display("FAIL F11 soft reset did not assert guest/cpu reset");
            $finish;
        end
        tick;
        if (!guest_reset_n || !cpu_reset_n || !cfg_valid) begin
            $display("FAIL F11 soft reset did not release guest with cfg intact");
            $finish;
        end
        soft_reset_key = 1'b0;
        tick;

        // 6. F12 return to loader
        recovery_key = 1'b1;
        tick; tick;
        if (!boot_overlay || !sd_owner_boot || !boot_recovery || guest_reset_n) begin
            $display("FAIL F12 return to loader");
            $finish;
        end

        $display("PASS boot_orchestrator: reset, validation, ROM promotion, F11 soft reset, F12 return");
        $finish;
    end
endmodule
