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
    integer timing = 4;
    reg trace = 0, loader_writes = 0;
    initial begin
        if (!$value$plusargs("timing=%d", timing))
            timing = 4;
        trace = $test$plusargs("trace_bus");
        loader_writes = $test$plusargs("loader_writes");
    end
    wire [2:0] timing_id = timing[2:0];
    wire [2:0] paging_id = timing == 2 ? 3'd3 : 3'd1;
    wire tk = timing == 3 || timing == 4;
    wire [8:0] picture_y = timing == 4 ? 9'd32 : timing == 5 ? 9'd64 : 9'd56;
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
    localparam [21:0] SHARE_ADDR = 22'h014100;
    reg shared_active = 0;
    integer shared_ties = 0, shared_replies = 0, shared_signatures = 0;
    wire shared_request = shared_active && cpu_mem_req && cpu_mem_addr == SHARE_ADDR &&
                          shared_ties < 3 && cpu_mem_we == (shared_ties != 1);
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
        .clk_sys(clk_sys), .rst_n(rst_n), .cfg_timing_id(timing_id), .cfg_psg_enable(1'b0),
        .ce_cpu(ce_cpu), .ce_ula(ce_ula), .ce_psg(ce_psg), .clocks_ready(clocks_ready)
    );
`ifdef REGISTERED_CPU_CLOCK
    wire clk_cpu;
    cpu_clock_model #(.FABRIC_PERIOD_PS(CLK_PS)) cpu_clock (clk_cpu);
`endif
    core_subsystem dut (
`ifdef REGISTERED_CPU_CLOCK
        .clk_cpu(clk_cpu),
`endif
        .clk_sys(clk_sys), .rst_n(rst_n), .cpu_reset_n(guest_reset_n),
        .guest_reset_n(guest_reset_n), .cpu_quiesce(cpu_quiesce), .cpu_quiesced(cpu_quiesced),
        .boot_overlay(1'b0), .cfg_valid(1'b1), .cfg_timing_id(timing_id),
        .cfg_paging_id(paging_id), .cfg_rom_valid_mask(4'd1), .cfg_psg_enable(1'b0), .cfg_disk_kind(2'd0),
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
        .ld_mem_req(ld_mem_req || shared_request), .ld_mem_accept(ld_mem_accept),
        .ld_mem_addr(shared_request ? SHARE_ADDR : ld_mem_addr),
        .ld_mem_we(shared_request ? shared_ties != 0 : ld_mem_we),
        .ld_mem_wdata(shared_request ? (shared_ties == 1 ? 8'ha6 : 8'h69) : ld_mem_wdata),
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
    integer memory_waits = 0, read_deadline_misses = 0, write_deadline_misses = 0;
    integer loader_transactions = 0;
    reg requested = 0, expected_read = 0;
    reg prev_read = 0, prev_mem_cycle = 0;
    integer x_t1, y_t1, phase, slots, expected_cpu_waits = 0;
    reg check_t2 = 0;
    reg [7:0] expected_signature = 8'h10;
    always @(posedge clk_sys) begin
        tick = tick + 1;
        if (guest_reset_n) begin
            if (dut.pos_phase && dut.mem_delay)
                memory_waits = memory_waits + 1;
            if (dut.late_read && !dut.mem_delay)
                read_deadline_misses = read_deadline_misses + 1;
            if (dut.late_write)
                write_deadline_misses = write_deadline_misses + 1;
            if (trace && (dut.cpu_ce_p || dut.cpu_ce_n))
                $display("TRACE P %0d %b%b %h %b%b%b%b%b%b %h %h",
                         tick, dut.cpu_ce_p, dut.cpu_ce_n, dut.addr, dut.m1_n, dut.mreq_n,
                         dut.iorq_n, dut.rd_n, dut.wr_n, dut.rfsh_n, dut.cpu_DO, dut.cpu_DI);
            if (trace && dut.mem_read_due && dut.cpu_ce_p)
                $display("TRACE R %0d %h %h", tick, dut.addr, dut.cpu_DI);
            if (trace && dut.pos_phase && dut.mem_delay)
                $display("TRACE C %0d %0d %0d %h", tick, ula_x, ula_y, dut.addr);
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
                if (trace && cpu_mem_we) begin
                    $display("TRACE W %h %h", cpu_mem_addr, cpu_mem_wdata);
                    if (loader_writes)
                        $display("TRACE A %h %h", cpu_mem_addr, cpu_mem_wdata);
                end
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
            if (tk && dut.memory_cycle && !prev_mem_cycle) begin
                check_t2 = 1;
                slots = 0;
                if (dut.addr[15:14] == 2'b01 && y_t1 >= picture_y && y_t1 < picture_y + 192 &&
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
        if (loader_writes && stress && ld_mem_req && ld_mem_accept) begin
            if (trace && ld_mem_we)
                $display("TRACE A %h %h", ld_mem_addr, ld_mem_wdata);
            loader_transactions = loader_transactions + 1;
            ld_mem_we <= loader_transactions % 17 == 0;
            ld_mem_addr <= loader_transactions % 17 == 0 ? 22'h030000 : 22'h020000;
            ld_mem_wdata <= loader_transactions[7:0];
        end
        if (loader_writes && trace && guest_reset_n && memory.issue_req &&
            memory.issue_accept && memory.issue_we)
            $display("TRACE M %h %h", memory.issue_addr, memory.issue_wdata);
        if (stress && ld_mem_rvalid) begin
            if (ld_mem_rdata !== 8'hc3) begin
                $display("FAIL Loader read data changed during CPU traffic");
                $finish;
            end
            loader_reads = loader_reads + 1;
        end
    end

`ifdef REGISTERED_CPU_CLOCK
    integer accepted_phases = 0, delivered_phases = 0;
    reg previous_confirmed_read = 0, confirm_pending = 0;
    reg [15:0] confirmed_addr;
    integer confirmed_reads = 0;
    reg [10:0] expected_phase;
    always @(posedge clk_sys) begin
        previous_confirmed_read <= dut.guest_read_before_strobes;
        if (rst_n && dut.guest_read_before_strobes && !previous_confirmed_read) begin
            if (confirm_pending)
                $fatal(1, "FAIL second confirmed read before the previous CPU phase");
            confirmed_addr = dut.addr;
            confirm_pending = 1;
        end
        if (rst_n && (dut.cpu_ce_p || dut.cpu_ce_n)) begin
            if (accepted_phases != delivered_phases)
                $fatal(1, "FAIL accepted two phases without delivering the first");
            expected_phase = {dut.cpu_ce_p, dut.cpu_ce_n, dut.ula_int_n, dut.cpu_DI};
            accepted_phases = accepted_phases + 1;
        end
    end
    always @(posedge clk_cpu) begin
        if (rst_n && (dut.cpu_bridge.cpu_ce_p || dut.cpu_bridge.cpu_ce_n)) begin
            if (delivered_phases + 1 != accepted_phases ||
                {dut.cpu_bridge.cpu_ce_p, dut.cpu_bridge.cpu_ce_n,
                 dut.cpu_bridge.cpu_int_n, dut.cpu_bridge.cpu_data_in} !== expected_phase)
                $fatal(1, "FAIL phase delivery order or sampled payload changed");
            delivered_phases = delivered_phases + 1;
            if (confirm_pending) begin
                if (!dut.cpu_bridge.cpu_ce_n)
                    $fatal(1, "FAIL confirmed read on a positive phase");
                #1;
                if ({dut.cpu_bridge.cpu_addr, dut.cpu_bridge.cpu_mreq_n,
                     dut.cpu_bridge.cpu_rd_n, dut.cpu_bridge.cpu_wr_n, dut.cpu_bridge.cpu_rfsh_n}
                    !== {confirmed_addr, 4'b0011})
                    $fatal(1, "FAIL confirmed read differs from the T80pa address or strobes");
                confirm_pending = 0;
                confirmed_reads = confirmed_reads + 1;
            end
        end
    end
`endif

    // Compare DInst and DI_Reg sample edges on the translated T80, rather
    // than comparing earlier fabric values while a RAM response is pending.
`ifdef REGISTERED_CPU_CLOCK
    `define TRACE_T80PA dut.cpu_bridge.cpu.cpu
    wire sample_clk = clk_cpu;
    wire sample_p = dut.cpu_bridge.cpu_ce_p;
    wire sample_n = dut.cpu_bridge.cpu_ce_n;
    wire [7:0] sample_data = dut.cpu_bridge.cpu_data_in;
`else
    `define TRACE_T80PA dut.cpu.cpu
    wire sample_clk = clk_sys;
    wire sample_p = dut.cpu_ce_p;
    wire sample_n = dut.cpu_ce_n;
    wire [7:0] sample_data = dut.cpu_DI;
`endif
    integer sample_phase = 0;
    always @(posedge sample_clk) begin
        if (trace && rst_n && (sample_p || sample_n)) begin
            sample_phase = sample_phase + 1;
            if ((sample_n && `TRACE_T80PA.tstate == 3'd3 && `TRACE_T80PA.busak) ||
                (sample_p && `TRACE_T80PA.u0.clken && `TRACE_T80PA.tstate == 3'd2 &&
                 (`TRACE_T80PA.mcycle == 3'd1 ||
                  (`TRACE_T80PA.mcycle == 3'd7 && `TRACE_T80PA.u0.iset == 2'b01))))
                $display("TRACE D %0d %b%b %h", sample_phase, sample_p, sample_n, sample_data);
        end
    end
    `undef TRACE_T80PA

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

    // The controller is idle going into each directed tie. Values are
    // observed by the real guest after reading the shared byte.
    always @(posedge clk_sys) begin
        if (shared_active) begin
            if (shared_request && (cpu_mem_accept || ld_mem_accept)) begin
                if (!cpu_mem_accept || !ld_mem_accept)
                    $fatal(1, "FAIL expected CPU/loader tie on shared byte at case %0d", shared_ties);
                $display("TIE case=%0d tick=%0d cpu_we=%b addr=%h", shared_ties, tick, cpu_mem_we, cpu_mem_addr);
                shared_ties <= shared_ties + 1;
            end
            if (ld_mem_rvalid) begin
                if (shared_replies != 0 || ld_mem_rdata !== 8'h5a)
                    $fatal(1, "FAIL loader read did not see the simultaneous CPU write");
                shared_replies <= shared_replies + 1;
            end
            if (cpu_mem_req && cpu_mem_accept && cpu_mem_we &&
                cpu_mem_addr >= 22'h008000 && cpu_mem_addr < 22'h008003) begin
                if (cpu_mem_addr !== 22'h008000 + shared_signatures ||
                    cpu_mem_wdata !== (shared_signatures == 0 ? 8'h5a :
                                      shared_signatures == 1 ? 8'ha6 : 8'h69))
                    $fatal(1, "FAIL shared-byte CPU readback case %0d gave %h", shared_signatures, cpu_mem_wdata);
                $display("READBACK case=%0d data=%h", shared_signatures, cpu_mem_wdata);
                shared_signatures <= shared_signatures + 1;
            end
        end
    end

    task same_byte_arbitration;
        begin
            emit('h3e); emit('h5a);                     // LD A,5A
            emit('h32); emit(0); emit('h41);             // LD (4100),A / loader read
            emit('h3a); emit(0); emit('h41);             // LD A,(4100) / loader writes A6
            emit('h32); emit(0); emit('h80);             // save 5A
            emit('h3a); emit(0); emit('h41);
            emit('h32); emit(1); emit('h80);             // save A6
            emit('h3e); emit('hc3);
            emit('h32); emit(0); emit('h41);             // LD (4100),A / loader writes 69
            emit('h3a); emit(0); emit('h41);
            emit('h32); emit(2); emit('h80);             // save 69
            emit('h76);
            wait (mem_idle);
            @(negedge clk_sys);
            shared_active = 1;
            guest_reset_n = 1;
            wait (shared_signatures == 3);
            @(negedge clk_sys);
            cpu_quiesce = 1;
            wait (mem_idle && cpu_quiesced);
            if (shared_ties != 3 || shared_replies != 1 || cpu_mem_deadline_miss)
                $fatal(1, "FAIL shared-byte ordering coverage or CPU deadline");
            $display("PASS shared-byte arbitration while guest runs: 3 ties, 1 loader reply, 3 CPU readbacks, min margin %0d", min_slack);
            $finish;
        end
    endtask

    integer i;
    initial begin
        #1 rst_n = 0;
        repeat (3) @(negedge clk_sys);
        rst_n = 1;
        wait (mem_ready && clocks_ready);
        ld_write('h20000, 'hc3); ld_write('h20001, 0); ld_write('h20002, 'h40); // JP 4000
        if ($test$plusargs("same_byte"))
            same_byte_arbitration;
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
        wait (ula_y == picture_y + 6);
        @(negedge clk_sys);
        cpu_quiesce = 1;
        // Retire the loader request before stopping its stream.
        @(posedge clk_sys);
        while (!ld_mem_accept)
            @(posedge clk_sys);
        @(negedge clk_sys);
        ld_mem_req = 0;
        wait (mem_idle && cpu_quiesced);
`ifdef REGISTERED_CPU_CLOCK
        if (accepted_phases != delivered_phases || dut.phase_pending || confirm_pending || confirmed_reads == 0)
            $fatal(1, "FAIL CPU quiesced with undelivered phase");
        $display("PHASES accepted=%0d delivered=%0d confirmed_reads=%0d",
                 accepted_phases, delivered_phases, confirmed_reads);
`endif
        $display("METRICS timing=%0d reads=%0d max_service=%0d min_margin=%0d contention=%0d late_reads=%0d late_writes=%0d refresh_overlaps=%0d loader_reads=%0d signatures=%0d",
                 timing, reads, max_read_ticks, min_slack, memory_waits, read_deadline_misses,
                 write_deadline_misses, overlap_refresh, loader_reads, signatures);
        if (cpu_mem_deadline_miss || signatures < 15 || overlap_refresh < 10 ||
            (tk && expected_cpu_waits < 20) || (timing == 5 && memory_waits != 0) ||
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
