`timescale 1ps/1ps

module core_sdram_tb;
    localparam CLK_PS = 11640;
    reg clk_sys = 0, sdram_clk = 0;
    always #(CLK_PS/2) clk_sys = !clk_sys;
    initial begin
        #(CLK_PS/2 - 1000);
        forever begin
            sdram_clk = !sdram_clk;
            #(CLK_PS/2);
        end
    end

    reg rst_n = 1, guest_reset_n = 0, cpu_quiesce = 0;
    wire cpu_quiesced;
    wire mem_ready, mem_idle, clocks_ready, ce_ula, ce_cpu, ce_psg;
    wire cpu_mem_req, cpu_mem_accept, cpu_mem_we, cpu_mem_rvalid, cpu_mem_deadline_miss;
    wire [21:0] cpu_mem_addr;
    wire [7:0] cpu_mem_wdata, cpu_mem_rdata;
    reg ld_mem_req = 0, ld_mem_we = 0;
    wire ld_mem_accept, ld_mem_rvalid;
    reg [21:0] ld_mem_addr = 0;
    reg [7:0] ld_mem_wdata = 0;
    wire [7:0] ld_mem_rdata;
    wire screen_rd_req, screen_rd_bank7, screen_rd_valid, ula_px_ce;
    wire [12:0] screen_rd_offset;
    wire [7:0] screen_rd_data;
    wire [9:0] ula_x;
    wire [8:0] ula_y;
    wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n;
    wire [12:0] sdram_a;
    wire [1:0] sdram_ba, sdram_dqm;
    wire [15:0] sdram_dq;
    wire [3:0] sdram_cmd = {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n};

    video_clock_enables enables (
        .clk_sys(clk_sys), .rst_n(rst_n), .cfg_timing_id(3'd4), .cfg_psg_enable(1'b0),
        .ce_cpu(ce_cpu), .ce_ula(ce_ula), .ce_psg(ce_psg), .clocks_ready(clocks_ready)
    );
    core_subsystem dut (
        .clk_sys(clk_sys), .rst_n(rst_n), .cpu_reset_n(guest_reset_n),
        .guest_reset_n(guest_reset_n), .cpu_quiesce(cpu_quiesce), .cpu_quiesced(cpu_quiesced),
        .boot_overlay(1'b0), .cfg_valid(1'b1), .cfg_timing_id(3'd4),
        .cfg_paging_id(3'd1), .cfg_rom_valid_mask(4'd1), .cfg_psg_enable(1'b0), .cfg_disk_kind(2'd0),
        .cfg_input_map_id(2'd2), .cfg_joy1_b_map(2'd0), .cfg_joy2_b_map(2'd0),
        .ce_cpu(ce_cpu), .ce_ula(ce_ula), .ce_psg(ce_psg), .psg_ce(),
        .mem_ready(mem_ready), .cpu_mem_req(cpu_mem_req), .cpu_mem_accept(cpu_mem_accept),
        .cpu_mem_addr(cpu_mem_addr), .cpu_mem_we(cpu_mem_we), .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rvalid(cpu_mem_rvalid), .cpu_mem_rdata(cpu_mem_rdata),
        .cpu_mem_deadline_miss(cpu_mem_deadline_miss),
        .boot_bus_req(), .boot_bus_io(), .boot_bus_we(), .boot_bus_addr(),
        .boot_bus_wdata(), .boot_bus_ready(1'b0), .boot_bus_rdata(8'hff),
        .screen_rd_req(screen_rd_req), .screen_rd_bank7(screen_rd_bank7), .screen_rd_offset(screen_rd_offset),
        .screen_rd_valid(screen_rd_valid), .screen_rd_data(screen_rd_data),
        .ula_px_ce(ula_px_ce), .ula_color(), .ula_x(ula_x), .ula_y(ula_y),
        .ula_hs_n(), .ula_vs_n(), .ula_blank(), .key_matrix_n({40{1'b1}}),
        .joy1(6'd0), .joy2(6'd0), .ear_bit(1'b1), .mic_bit(), .beeper_bit(),
        .ay_req(), .ay_op(), .ay_wdata(), .ay_rdata(8'hff),
        .disk_req(), .disk_we(), .disk_reg(), .disk_wdata(), .disk_rdata(8'hff), .disk_motor()
    );
    mem_subsystem #(.ROW_BITS(11), .COL_BITS(8), .POWERUP_CYCLES(16)) memory (
        .clk_sys(clk_sys), .rst_n(rst_n), .mem_ready(mem_ready), .mem_idle(mem_idle),
        .cpu_mem_req(cpu_mem_req), .cpu_mem_accept(cpu_mem_accept),
        .cpu_mem_addr(cpu_mem_addr), .cpu_mem_we(cpu_mem_we), .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rvalid(cpu_mem_rvalid), .cpu_mem_rdata(cpu_mem_rdata),
        .ld_mem_req(ld_mem_req), .ld_mem_accept(ld_mem_accept), .ld_mem_addr(ld_mem_addr),
        .ld_mem_we(ld_mem_we), .ld_mem_wdata(ld_mem_wdata),
        .ld_mem_rvalid(ld_mem_rvalid), .ld_mem_rdata(ld_mem_rdata),
        .screen_rd_req(screen_rd_req), .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(screen_rd_offset), .screen_rd_valid(screen_rd_valid), .screen_rd_data(screen_rd_data),
        .sdram_cke(sdram_cke), .sdram_cs_n(sdram_cs_n), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n), .sdram_a(sdram_a),
        .sdram_ba(sdram_ba), .sdram_dqm(sdram_dqm), .sdram_dq(sdram_dq)
    );
    sdram_x16_model #(.ROW_BITS(11), .COL_BITS(8), .POWERUP_PS(16 * CLK_PS)) chip (
        .rst_n(rst_n), .clk(sdram_clk), .cke(sdram_cke), .cs_n(sdram_cs_n), .ras_n(sdram_ras_n),
        .cas_n(sdram_cas_n), .we_n(sdram_we_n), .a(sdram_a), .ba(sdram_ba),
        .dqm(sdram_dqm), .dq(sdram_dq), .column_word_addr()
    );

    reg stress = 0;
    integer tick = 0, request_tick, max_read_ticks = 0, min_slack = 99, last_response_tick;
    integer reads = 0, overlap_refresh = 0, signatures = 0, loader_reads = 0;
    reg requested = 0, expected_read = 0;
    reg prev_read = 0, prev_mem_cycle = 0;
    integer x_t1, y_t1, phase, slots, expected_cpu_waits = 0;
    reg check_t2 = 0;
    reg [7:0] expected_signature = 8'h10;
    always @(posedge clk_sys) begin
        tick = tick + 1;
        if (cpu_mem_deadline_miss) begin
            $display("FAIL CPU missed its memory edge in SDRAM stress");
            $finish;
        end
        if (guest_reset_n) begin
            if (dut.mem_read && !prev_read)
                if (!cpu_mem_req || cpu_mem_we) begin
                    $display("FAIL Read was not issued on first available edge, addr=%h", dut.addr);
                    $finish;
                end
            prev_read <= dut.mem_read;
            if (cpu_mem_req && !requested) begin
                requested <= 1;
                request_tick = tick;
            end
            if (cpu_mem_req && cpu_mem_accept) begin
                requested <= 0;
                if (!cpu_mem_we) begin
                    if (expected_read) begin
                        $display("FAIL Overlapping CPU reads");
                        $finish;
                    end
                    expected_read <= 1;
                end
                if (cpu_mem_we && cpu_mem_addr == 22'h17f00) begin
                    if (cpu_mem_wdata !== expected_signature) begin
                        $display("FAIL SDRAM diagnostic expected %h got %h", expected_signature, cpu_mem_wdata);
                        $finish;
                    end
                    expected_signature <= expected_signature + 8'd1;
                    signatures = signatures + 1;
                end
            end
            if (cpu_mem_rvalid) begin
                if (!expected_read) begin
                    $display("FAIL Unsolicited CPU response");
                    $finish;
                end
                expected_read <= 0;
                reads = reads + 1;
                last_response_tick = tick;
                if (tick - request_tick > max_read_ticks)
                    max_read_ticks = tick - request_tick;
            end
            if (dut.mem_read_due && dut.cpu_ce_p && tick - last_response_tick < min_slack)
                min_slack = tick - last_response_tick;
            if (stress && sdram_cmd == 4'b0001 && (expected_read || cpu_mem_req))
                overlap_refresh = overlap_refresh + 1;

            // Derive the TK waits independently from the T1 coordinates
            // and check the actual T80 enables, including across a burst.
            if (dut.memory_cycle && !prev_mem_cycle) begin
                check_t2 = 1;
                slots = 0;
                if (dut.addr[15:14] == 2'b01 && y_t1 >= 32 && y_t1 < 224 &&
                    x_t1 >= 42 && x_t1 < 298) begin
                    phase = ((x_t1 - 42) / 2) % 8;
                    if (phase < 6)
                        slots = 6 - phase;
                end
            end
            if (ce_cpu) begin
                if (check_t2) begin
                    if (slots != 0) begin
                        if (dut.cpu_ce_p) begin
                            $display("FAIL Missing TK memory contention slot");
                            $finish;
                        end
                        slots = slots - 1;
                        expected_cpu_waits = expected_cpu_waits + 1;
                    end else begin
                        if (!dut.cpu_ce_p) begin
                            $display("FAIL Extra TK memory wait");
                            $finish;
                        end
                        check_t2 = 0;
                    end
                end
                x_t1 = ula_x;
                y_t1 = ula_y;
            end
            prev_mem_cycle <= dut.memory_cycle;
        end
        if (stress && ld_mem_rvalid) begin
            if (ld_mem_rdata !== 8'hc3) begin
                $display("FAIL Loader read data changed during CPU traffic");
                $finish;
            end
            loader_reads = loader_reads + 1;
        end
    end

    task ld_write;
        input [21:0] address;
        input [7:0] value;
        begin
            @(negedge clk_sys);
            ld_mem_req = 1;
            ld_mem_addr = address;
            ld_mem_we = 1;
            ld_mem_wdata = value;
            @(posedge clk_sys);
            while (!ld_mem_accept)
                @(posedge clk_sys);
            @(negedge clk_sys);
            ld_mem_req = 0;
        end
    endtask

    integer loc = 'h14000;
    task emit;
        input [7:0] value;
        begin
            ld_write(loc, value);
            loc = loc + 1;
        end
    endtask

    integer i;
    initial begin
        #1 rst_n = 0;
        repeat (3) @(negedge clk_sys);
        rst_n = 1;
        wait (mem_ready && clocks_ready);
        ld_write('h20000, 'hc3); ld_write('h20001, 0); ld_write('h20002, 'h40); // JP 4000
        // Copy 16 bytes with LDIR, then increment the last byte at the
        // source and store it to the externally monitored signature.
        emit('h21); emit(0); emit('h41); // LD HL,4100
        emit('h11); emit(0); emit('h42); // LD DE,4200
        emit('h01); emit(16); emit(0);   // LD BC,16
        emit('hed); emit('hb0);          // LDIR
        emit('h3a); emit('h0f); emit('h42);
        emit('h3c);
        emit('h32); emit('h0f); emit('h41);
        emit('h32); emit(0); emit('h7f);
        emit('hc3); emit(0); emit('h40);
        for (i = 0; i < 16; i = i + 1)
            ld_write('h14100 + i, i);
        wait (mem_idle);
        @(negedge clk_sys);
        guest_reset_n = 1;
        stress = 1;
        ld_mem_we = 0;
        ld_mem_addr = 'h20000;
        ld_mem_req = 1;
        wait (ula_y == 38);
        @(negedge clk_sys);
        cpu_quiesce = 1;
        // Retire the loader request before stopping its stream.
        @(posedge clk_sys);
        while (!ld_mem_accept)
            @(posedge clk_sys);
        @(negedge clk_sys);
        ld_mem_req = 0;
        wait (mem_idle && cpu_quiesced);
        if (signatures < 15 || overlap_refresh < 10 || expected_cpu_waits < 20 ||
            loader_reads < 100 || min_slack < 0 || max_read_ticks >= 35) begin
            $display("FAIL Insufficient coverage: signatures=%d refresh=%d waits=%d loader=%d slack=%d delay=%d",
                     signatures, overlap_refresh, expected_cpu_waits, loader_reads, min_slack, max_read_ticks);
            $finish;
        end
        $display("PASS SDRAM stress: %0d CPU reads, max %0d fabric clocks to valid, min %0d clocks of sample slack",
                 reads, max_read_ticks, min_slack);
        $display("PASS %0d refresh overlaps, %0d model waits and %0d loader reads", overlap_refresh, expected_cpu_waits, loader_reads);
        $finish;
    end

    initial begin
        #6000000000;
        $display("FAIL SDRAM stress timeout");
        $finish;
    end
endmodule
