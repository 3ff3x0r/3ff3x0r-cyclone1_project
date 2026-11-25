`timescale 1ns/1ps

module boot_completion_tb;
    localparam [7:0] SD_BYTE = 8'ha6;
    reg clk_sys = 1'b0, rst_n = 1'b0;
    always #5 clk_sys = !clk_sys;

    integer tick = 0;
    always @(negedge clk_sys) tick = tick + 1;
    wire ce_cpu = tick % 24 == 12;
    wire ce_ula = tick % 12 == 0;
    wire boot_req, boot_io, boot_we, boot_ready;
    wire [15:0] boot_addr;
    wire [7:0] boot_wdata, boot_rdata;

    wire clk_cpu;
    cpu_clock_model #(.FABRIC_PERIOD_PS(10000)) cpu_clock (clk_cpu);
    core_subsystem core (
        .clk_sys(clk_sys), .clk_cpu(clk_cpu), .rst_n(rst_n), .cpu_reset_n(rst_n), .guest_reset_n(1'b0),
        .cpu_quiesce(1'b0), .boot_overlay(1'b1), .cfg_valid(1'b0),
        .cfg_timing_id(3'd0), .cfg_paging_id(3'd0), .cfg_rom_valid_mask(4'd0),
        .cfg_psg_enable(1'b0), .cfg_disk_kind(2'd0), .cfg_input_map_id(2'd0),
        .cfg_joy1_b_map(2'd0), .cfg_joy2_b_map(2'd0),
        .ce_cpu(ce_cpu), .ce_ula(ce_ula), .ce_psg(1'b0),
        .mem_ready(1'b1), .cpu_mem_accept(1'b0), .cpu_mem_rvalid(1'b0),
        .cpu_mem_rdata(8'd0), .screen_rd_valid(1'b0), .screen_rd_data(8'd0),
        .key_matrix_n({40{1'b1}}), .joy1(6'd0), .joy2(6'd0), .ear_bit(1'b1),
        .ay_rdata(8'hff), .disk_rdata(8'hff),
        .boot_bus_req(boot_req), .boot_bus_io(boot_io), .boot_bus_we(boot_we),
        .boot_bus_addr(boot_addr), .boot_bus_wdata(boot_wdata),
        .boot_bus_ready(boot_ready), .boot_bus_rdata(boot_rdata)
    );

    wire sd_ready;
    wire [7:0] sd_rdata;
    wire mem_req, mem_we;
    wire [21:0] mem_addr;
    wire [7:0] mem_wdata;
    // Backpressure the boot RAM write until a scheduled positive phase.
    wire mem_accept = ce_cpu;
    boot_bus_adapter adapter (
        .clk_sys(clk_sys), .rst_n(rst_n), .boot_overlay(1'b1), .mem_ready(1'b1),
        .boot_bus_req(boot_req), .boot_bus_io(boot_io), .boot_bus_we(boot_we),
        .boot_bus_addr(boot_addr), .boot_bus_wdata(boot_wdata),
        .boot_bus_ready(boot_ready), .boot_bus_rdata(boot_rdata),
        .sd_bridge_ready(sd_ready), .sd_bridge_rdata(sd_rdata),
        .boot_mem_req(mem_req), .boot_mem_accept(mem_accept), .boot_mem_we(mem_we),
        .boot_mem_addr(mem_addr), .boot_mem_wdata(mem_wdata),
        .boot_mem_rvalid(1'b0), .boot_mem_rdata(8'd0)
    );

    wire data_read = boot_io && !boot_we && boot_addr[7:0] == 8'hd5;
    // Present D5 one clock before a negative phase. The real bridge spends
    // that clock fetching from its synchronous RAM, then accepts at the phase.
    wire sd_req_to_bridge = boot_req && (!data_read || tick % 24 >= 23 || tick % 24 == 0);
    wire block_req, block_rx_ready;
    reg block_active = 1'b0;
    reg [9:0] block_bytes = 10'd0;
    wire block_done = block_active && block_bytes == 10'd512;
    wire block_rx_valid = block_active && !block_done;
    boot_sd_bridge sd_bridge (
        .clk_sys(clk_sys), .rst_n(rst_n), .sd_owner_boot(1'b1), .media_quiesce(1'b0),
        .boot_bus_req(sd_req_to_bridge), .boot_bus_io(boot_io), .boot_bus_we(boot_we),
        .boot_bus_addr(boot_addr), .boot_bus_wdata(boot_wdata),
        .boot_bus_ready(sd_ready), .boot_bus_rdata(sd_rdata),
        .sd_blk_req(block_req), .sd_blk_ready(1'b1),
        .sd_blk_rx_valid(block_rx_valid), .sd_blk_rx_ready(block_rx_ready),
        .sd_blk_rx_data(block_bytes == 0 ? SD_BYTE : 8'h5b),
        .sd_blk_done(block_done), .sd_blk_error(4'd0)
    );

    task fail;
        input [8*96-1:0] reason;
        begin
            $display("FAIL boot completion: %0s (tick %0d)", reason, tick);
            $stop;
        end
    endtask

    integer data_waits = 0, data_accepts = 0, data_pops = 0;
    integer data_consumes = 0, writes = 0;
    reg data_sample_pending = 0;
    always @(posedge clk_sys) begin
        if (rst_n) begin
            if (block_req)
                block_active <= 1'b1;
            else if (block_done)
                block_active <= 1'b0;
            else if (block_rx_valid && block_rx_ready)
                block_bytes <= block_bytes + 1'b1;

            if (data_read && sd_req_to_bridge && !sd_ready)
                data_waits = data_waits + 1;
            if (sd_bridge.data_take)
                data_pops = data_pops + 1;

            if (data_read && boot_ready) begin
                if (data_accepts != 0 || data_waits != 1 || !core.neg_phase ||
                    core.cpu_ce_n !== 1'b0)
                    fail("SD DATA acceptance did not stall the scheduled negative phase");
                if (core.read_done || core.cpu_DI !== 8'hff || boot_rdata !== SD_BYTE)
                    fail("SD DATA was visible to the CPU before the accepting edge");
                data_accepts <= data_accepts + 1;
            end

            if (mem_req && mem_accept) begin
                if (writes != 0 || !mem_we || mem_addr !== 22'h014000 ||
                    mem_wdata !== SD_BYTE || data_consumes != 1)
                    fail("CPU did not store the single SD DATA byte exactly once");
                if (!boot_ready || !core.pos_phase || core.cpu_ce_p !== 1'b0)
                    fail("RAM write acceptance did not stall the scheduled positive phase");
                writes = writes + 1;
            end

            if (data_accepts != 0 && core.io_cycle && boot_addr[7:0] == 8'hd5) begin
                if (boot_req || boot_rdata !== 8'hff || !core.access_taken ||
                    !core.read_done || core.read_data !== SD_BYTE || core.cpu_DI !== SD_BYTE)
                    fail("SD DATA read did not hold the registered byte after acceptance");
                if (core.cpu_ce_n) begin
                    if (data_sample_pending || data_consumes != 0)
                        fail("SD DATA scheduled more than one CPU sample");
                    data_sample_pending <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk_cpu) begin
        if (rst_n && data_sample_pending && core.cpu_bridge.cpu_ce_n) begin
            if (core.cpu_bridge.cpu_data_in !== SD_BYTE)
                fail("T80pa did not receive the snapshotted SD DATA byte");
            #1;
            // Earlier negative phases can keep this I/O cycle active.
            // The T3 negative phase samples the byte and releases IORQ.
            if (core.cpu_bridge.cpu_iorq_n)
                data_consumes = data_consumes + 1;
            data_sample_pending <= 1'b0;
        end
    end

    initial begin
        repeat (3) @(negedge clk_sys);
        // LD A,1 / OUT (D4),A / poll D4 until data is valid /
        // IN A,(D5) / LD (4000),A / HALT.
        {adapter.boot_rom[0], adapter.boot_rom[1], adapter.boot_rom[2], adapter.boot_rom[3],
         adapter.boot_rom[4], adapter.boot_rom[5], adapter.boot_rom[6], adapter.boot_rom[7],
         adapter.boot_rom[8], adapter.boot_rom[9], adapter.boot_rom[10], adapter.boot_rom[11],
         adapter.boot_rom[12], adapter.boot_rom[13], adapter.boot_rom[14], adapter.boot_rom[15]}
            = 128'h3e01_d3d4_dbd4_e604_28fa_dbd5_320040_76;
        rst_n = 1'b1;
        wait (writes == 1);
        repeat (150) @(negedge clk_sys);
        if (data_accepts != 1 || data_waits != 1 || data_pops != 1 ||
            data_consumes != 1 || writes != 1)
            fail("Unexpected number of SD DATA reads, byte pops, or RAM writes");
        $display("PASS boot completion: phase-aligned RAM write and stalled SD DATA read each complete once");
        $finish;
    end

    initial begin
        #100000;
        fail("Timeout waiting for the boot program");
    end
endmodule
