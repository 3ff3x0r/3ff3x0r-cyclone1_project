`timescale 1ps/1ps

module mem_subsystem_tb #(
    parameter SMALL_SDRAM = 0
);
    localparam CLK_PS = 11640;
    localparam SDRAM_CLK_LEAD_PS = 1000;
    localparam POWERUP_CYCLES = SMALL_SDRAM ? 16 : (100000000 + CLK_PS - 1) / CLK_PS;
    localparam ROW_BITS = SMALL_SDRAM ? 11 : 13;
    localparam COL_BITS = SMALL_SDRAM ? 8 : 9;
    localparam [21:0] BANK5 = 22'h014000, BANK7 = 22'h01c000;
    localparam SCREEN_BYTES = 6912;
    localparam [3:0] CMD_READ = 4'b0101, CMD_WRITE = 4'b0100, CMD_REFRESH = 4'b0001;
    // In default timing, a write uses at most 6 clocks before the next
    // dispatch, a read uses 9, and one refresh can add 6. A CPU request
    // can arrive one clock after the first of two older transactions.
    localparam MAX_CPU_READ_CYCLES = 6 + 9 + 6 + 9 - 1;

    reg clk_sys = 0;
    always #(CLK_PS/2) clk_sys = ~clk_sys;

    // Emulate the dedicated PLL output. The SDRAM samples registered
    // commands on the leading edge, then clk_sys samples held read data.
    reg sdram_clk = 0;
    initial begin
        #(CLK_PS/2 - SDRAM_CLK_LEAD_PS);
        forever begin
            sdram_clk = ~sdram_clk;
            #(CLK_PS/2);
        end
    end

    reg rst_n = 1;
    wire mem_ready, mem_idle;

    reg cpu_mem_req = 0, cpu_mem_we = 0;
    reg [21:0] cpu_mem_addr = 0;
    reg [7:0] cpu_mem_wdata = 0;
    wire cpu_mem_accept, cpu_mem_rvalid;
    wire [7:0] cpu_mem_rdata;

    reg ld_mem_req = 0, ld_mem_we = 0;
    reg [21:0] ld_mem_addr = 0;
    reg [7:0] ld_mem_wdata = 0;
    wire ld_mem_accept, ld_mem_rvalid;
    wire [7:0] ld_mem_rdata;

    reg screen_rd_req = 0, screen_rd_bank7 = 0;
    reg [12:0] screen_rd_offset = 0;
    wire screen_rd_valid;
    wire [7:0] screen_rd_data;

    wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n;
    wire [12:0] sdram_a;
    wire [1:0] sdram_ba, sdram_dqm;
    wire [15:0] sdram_dq;

    mem_subsystem #(
        .ROW_BITS(ROW_BITS),
        .COL_BITS(COL_BITS),
        .POWERUP_CYCLES(POWERUP_CYCLES)
    ) dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .mem_ready(mem_ready),
        .mem_idle(mem_idle),
        .cpu_mem_req(cpu_mem_req),
        .cpu_mem_accept(cpu_mem_accept),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_we(cpu_mem_we),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rvalid(cpu_mem_rvalid),
        .cpu_mem_rdata(cpu_mem_rdata),
        .ld_mem_req(ld_mem_req),
        .ld_mem_accept(ld_mem_accept),
        .ld_mem_addr(ld_mem_addr),
        .ld_mem_we(ld_mem_we),
        .ld_mem_wdata(ld_mem_wdata),
        .ld_mem_rvalid(ld_mem_rvalid),
        .ld_mem_rdata(ld_mem_rdata),
        .screen_rd_req(screen_rd_req),
        .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(screen_rd_offset),
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

    wire [24:0] column_word_addr;
    sdram_x16_model #(
        .ROW_BITS(ROW_BITS),
        .COL_BITS(COL_BITS),
        .POWERUP_PS(SMALL_SDRAM ? POWERUP_CYCLES * CLK_PS : 100000000)
    ) model (
        .rst_n(rst_n),
        .clk(sdram_clk),
        .cke(sdram_cke),
        .cs_n(sdram_cs_n),
        .ras_n(sdram_ras_n),
        .cas_n(sdram_cas_n),
        .we_n(sdram_we_n),
        .a(sdram_a),
        .ba(sdram_ba),
        .dqm(sdram_dqm),
        .dq(sdram_dq),
        .column_word_addr(column_word_addr)
    );

    wire [3:0] command = {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n};

    // Reference bytes change in acceptance order. The FIFO independently
    // checks physical command order, bijective pin mapping and exactly-once
    // writes. The mirror reference changes only on a physical write edge.
    reg [7:0] expected_sdram [0:4194303];
    reg [7:0] expected_screen [0:2*SCREEN_BYTES-1];
    reg [21:0] queue_addr [0:7];
    reg [7:0] queue_data [0:7];
    reg queue_we [0:7];
    reg queue_loader [0:7];
    integer accepted = 0, issued = 0, writes = 0, read_commands = 0, responses = 0;
    integer cycle = 0;
    integer cpu_request_cycle = 0, cpu_read_start = 0, cpu_read_accept = 0;
    integer last_cpu_accept = -2, last_loader_accept = -2;
    integer next_slot, slot, screen_write_index, screen_read_index;
    integer max_cpu_req_latency = 0, max_cpu_accept_latency = 0;
    integer latency_reads = 0, refresh_under_load = 0, refresh_with_cpu_waiting = 0;
    integer both_accepted = 0, consecutive_cpu = 0;
    integer forward_bank5 = 0, forward_bank7 = 0, different_byte = 0;
    integer read_dq_sample_cycle = -1;
    reg cpu_read_live = 0, cpu_read_issued = 0;
    reg ld_read_live = 0, ld_read_issued = 0;
    reg [7:0] cpu_expected, ld_expected;
    reg [1:0] expected_mask;
    reg [1:0] read_dq_mask;
    reg [7:0] expected_screen_data;
    reg expected_screen_valid;
    reg stress = 0;

    function integer screen_index;
        input [21:0] addr;
        begin
            if (addr >= BANK5 && addr <= 22'h015aff)
                screen_index = int'(addr) - int'(BANK5);
            else if (addr >= BANK7 && addr <= 22'h01daff)
                screen_index = SCREEN_BYTES + int'(addr) - int'(BANK7);
            else
                screen_index = -1;
        end
    endfunction

    task record_accept;
        input loader;
        input we;
        input [21:0] addr;
        input [7:0] wdata;
        begin
            if (accepted - issued >= 2)
                $fatal(1, "More than two accepted transfers awaiting a column command");
            next_slot = accepted % 8;
            queue_loader[next_slot] = loader;
            queue_addr[next_slot] = addr;
            queue_data[next_slot] = wdata;
            queue_we[next_slot] = we;
            accepted = accepted + 1;

            if (we) begin
                expected_sdram[addr] = wdata;
            end else begin
                if ((^expected_sdram[addr]) === 1'bx)
                    $fatal(1, "Fixture read uninitialized byte %06x", addr);
                if (loader) begin
                    ld_read_live = 1;
                    ld_expected = expected_sdram[addr];
                end else begin
                    cpu_read_live = 1;
                    cpu_expected = expected_sdram[addr];
                    cpu_read_start = cpu_request_cycle;
                    cpu_read_accept = cycle;
                end
            end
        end
    endtask

    always @(posedge mem_ready) begin
        if (model.mode_at == 0 || $time - model.mode_at < 3 * CLK_PS)
            $fatal(1, "mem_ready asserted before the mode register settled");
    end

    always @(posedge clk_sys) begin
        cycle = cycle + 1;
        if (!rst_n) begin
            if ({mem_ready, mem_idle, cpu_mem_accept, ld_mem_accept,
                cpu_mem_rvalid, ld_mem_rvalid, screen_rd_valid} !== 7'b0)
                $fatal(1, "Interface must be inactive during reset");
            if ({command, sdram_cke, sdram_dqm, sdram_dq} !== {4'hf, 1'b0, 2'b11, 16'bz})
                $fatal(1, "SDRAM pins are unsafe during reset");
        end else begin
            if (mem_idle !== (mem_ready && accepted == issued && !cpu_read_live && !ld_read_live))
                $fatal(1, "Incorrect mem_idle at cycle %0d", cycle);
            if (!mem_ready && (cpu_mem_accept || ld_mem_accept))
                $fatal(1, "Accepted before mem_ready");
            if (cycle == read_dq_sample_cycle) begin
                if (read_dq_mask[0] && sdram_dq[7:0] !== 8'bz)
                    $fatal(1, "Low DQ lane driven during masked read");
                if (read_dq_mask[1] && sdram_dq[15:8] !== 8'bz)
                    $fatal(1, "High DQ lane driven during masked read");
            end
            if (command == CMD_REFRESH && stress) begin
                refresh_under_load = refresh_under_load + 1;
                if (cpu_read_live || cpu_mem_req)
                    refresh_with_cpu_waiting = refresh_with_cpu_waiting + 1;
            end

            if (cpu_mem_rvalid) begin
                if (!cpu_read_live || !cpu_read_issued || cycle <= cpu_read_accept ||
                    cpu_mem_rdata !== cpu_expected)
                    $fatal(1, "Unexpected CPU response %h, expected %h at cycle %0d",
                        cpu_mem_rdata, cpu_expected, cycle);
                if (cycle - cpu_read_start > MAX_CPU_READ_CYCLES)
                    $fatal(1, "CPU read took %0d clocks, budget %0d",
                        cycle - cpu_read_start, MAX_CPU_READ_CYCLES);
                if (stress) begin
                    latency_reads = latency_reads + 1;
                    if (cycle - cpu_read_start > max_cpu_req_latency)
                        max_cpu_req_latency = cycle - cpu_read_start;
                    if (cycle - cpu_read_accept > max_cpu_accept_latency)
                        max_cpu_accept_latency = cycle - cpu_read_accept;
                end
                cpu_read_live = 0;
                cpu_read_issued = 0;
                responses = responses + 1;
            end
            if (ld_mem_rvalid) begin
                if (!ld_read_live || !ld_read_issued || ld_mem_rdata !== ld_expected)
                    $fatal(1, "Unexpected loader response %h, expected %h at cycle %0d",
                        ld_mem_rdata, ld_expected, cycle);
                ld_read_live = 0;
                ld_read_issued = 0;
                responses = responses + 1;
            end

            // The PLL edge has sampled these pins. Check the observed
            // command and use this fabric edge to check mirror retirement.
            screen_write_index = -1;
            if (command == CMD_READ || command == CMD_WRITE) begin
                if (accepted == issued)
                    $fatal(1, "SDRAM column command without prior acceptance");
                slot = issued % 8;
                expected_mask = queue_addr[slot][0] ? 2'b01 : 2'b10;
                if (queue_we[slot] !== (command == CMD_WRITE) ||
                    sdram_dqm !== expected_mask ||
                    column_word_addr !== {4'b0, queue_addr[slot][21:1]})
                    $fatal(1, "Command order/lane/address mismatch for byte %06x: cmd=%b word=%h DQM=%b",
                        queue_addr[slot], command, column_word_addr, sdram_dqm);
                issued = issued + 1;

                if (command == CMD_WRITE) begin
                    if ((sdram_dqm[0] ? sdram_dq[15:8] : sdram_dq[7:0]) !== queue_data[slot])
                        $fatal(1, "Incorrect WRITE data at byte %06x", queue_addr[slot]);
                    writes = writes + 1;
                    screen_write_index = screen_index(queue_addr[slot]);
                    if (screen_write_index >= 0)
                        expected_screen[screen_write_index] = queue_data[slot];
                end else begin
                    read_commands = read_commands + 1;
                    read_dq_sample_cycle = cycle + 4;
                    read_dq_mask = expected_mask;
                    if (queue_loader[slot])
                        ld_read_issued = 1;
                    else
                        cpu_read_issued = 1;
                end
            end

            if (!cpu_mem_req)
                cpu_request_cycle = 0;
            else if (cpu_request_cycle == 0)
                cpu_request_cycle = cycle;

            if (cpu_mem_req && cpu_mem_accept) begin
                if (cpu_read_live)
                    $fatal(1, "Fixture broke CPU outstanding-read rule");
                if (last_cpu_accept == cycle - 1)
                    consecutive_cpu = consecutive_cpu + 1;
                last_cpu_accept = cycle;
                record_accept(0, cpu_mem_we, cpu_mem_addr, cpu_mem_wdata);
                cpu_request_cycle = 0;
            end
            if (ld_mem_req && ld_mem_accept) begin
                if (ld_read_live)
                    $fatal(1, "Fixture broke loader outstanding-read rule");
                last_loader_accept = cycle;
                record_accept(1, ld_mem_we, ld_mem_addr, ld_mem_wdata);
            end
            if (last_cpu_accept == cycle && last_loader_accept == cycle)
                both_accepted = both_accepted + 1;

            expected_screen_valid = screen_rd_req && screen_rd_offset < SCREEN_BYTES;
            if (expected_screen_valid) begin
                screen_read_index = (screen_rd_bank7 ? SCREEN_BYTES : 0) + int'(screen_rd_offset);
                expected_screen_data = expected_screen[screen_read_index];
                if (screen_read_index == screen_write_index) begin
                    if (screen_rd_bank7)
                        forward_bank7 = forward_bank7 + 1;
                    else
                        forward_bank5 = forward_bank5 + 1;
                end else if (screen_write_index >= 0) begin
                    different_byte = different_byte + 1;
                end
            end

            #1;
            if (screen_rd_valid !== expected_screen_valid ||
                (expected_screen_valid && screen_rd_data !== expected_screen_data))
                $fatal(1, "Screen bank %0d offset %04x returned %h, expected %h at cycle %0d",
                    screen_rd_bank7 ? 7 : 5, screen_rd_offset, screen_rd_data,
                    expected_screen_data, cycle);
        end
    end

    task cpu_transfer;
        input we;
        input [21:0] addr;
        input [7:0] data;
        begin
            @(negedge clk_sys);
            cpu_mem_req = 1;
            cpu_mem_we = we;
            cpu_mem_addr = addr;
            cpu_mem_wdata = data;
            @(posedge clk_sys);
            while (!cpu_mem_accept)
                @(posedge clk_sys);
            @(negedge clk_sys);
            cpu_mem_req = 0;
            cpu_mem_we = 0;
            if (!we) begin
                @(posedge clk_sys);
                while (!cpu_mem_rvalid)
                    @(posedge clk_sys);
            end
        end
    endtask

    // With 8 columns, all 13 row/bank bits fit in a two-byte pattern.
    // Fill a word in every row of every bank, then read after all writes.
    task check_small_chip_rows;
        integer row_bank;
        reg [21:0] addr;
        begin
            for (row_bank = 0; row_bank < 8192; row_bank = row_bank + 1) begin
                addr = {row_bank[12:0], 9'b0};
                loader_transfer(1, addr, row_bank[7:0]);
                loader_transfer(1, addr + 1'b1, {3'b101, row_bank[12:8]});
            end
            for (row_bank = 0; row_bank < 8192; row_bank = row_bank + 1) begin
                addr = {row_bank[12:0], 9'b0};
                loader_transfer(0, addr, 0);
                loader_transfer(0, addr + 1'b1, 0);
            end
        end
    endtask

    task loader_transfer;
        input we;
        input [21:0] addr;
        input [7:0] data;
        begin
            @(negedge clk_sys);
            ld_mem_req = 1;
            ld_mem_we = we;
            ld_mem_addr = addr;
            ld_mem_wdata = data;
            @(posedge clk_sys);
            while (!ld_mem_accept)
                @(posedge clk_sys);
            @(negedge clk_sys);
            ld_mem_req = 0;
            ld_mem_we = 0;
            if (!we) begin
                @(posedge clk_sys);
                while (!ld_mem_rvalid)
                    @(posedge clk_sys);
            end
        end
    endtask

    task drain;
        begin
            @(negedge clk_sys);
            while (!mem_idle)
                @(negedge clk_sys);
        end
    endtask

    task fill_screen;
        input bank7;
        integer offset;
        reg [21:0] base;
        reg [7:0] pattern;
        begin
            base = bank7 ? BANK7 : BANK5;
            for (offset = 0; offset < SCREEN_BYTES; offset = offset + 1) begin
                pattern = offset[7:0] ^ {3'b0, offset[12:8]} ^ (bank7 ? 8'h97 : 8'h52);
                if (bank7)
                    loader_transfer(1, base + offset[21:0], pattern);
                else
                    cpu_transfer(1, base + offset[21:0], pattern);
            end
        end
    endtask

    task scan_screens;
        integer offset;
        integer last_offset;
        begin
            last_offset = SCREEN_BYTES-1;
            for (offset = 0; offset <= last_offset; offset = offset + 1) begin
                @(negedge clk_sys);
                screen_rd_req = 1;
                screen_rd_bank7 = 0;
                screen_rd_offset = offset[12:0];
                @(negedge clk_sys);
                screen_rd_bank7 = 1;
            end
            @(negedge clk_sys);
            screen_rd_req = 0;
        end
    endtask

    task read_through_commit;
        input bank7;
        input [12:0] read_offset;
        input [12:0] write_offset;
        input [7:0] data;
        reg [21:0] base;
        begin
            base = bank7 ? BANK7 : BANK5;
            @(negedge clk_sys);
            screen_rd_req = 1;
            screen_rd_bank7 = bank7;
            screen_rd_offset = read_offset;
            if (bank7)
                cpu_transfer(1, base + {9'b0, write_offset}, data);
            else
                loader_transfer(1, base + {9'b0, write_offset}, data);
            drain;
            // Check the stored byte again after the forwarding cycle.
            screen_rd_offset = write_offset;
            @(negedge clk_sys);
            screen_rd_req = 0;
        end
    endtask

    // Exercise each byte address bit with distinguishable data. The test
    // starts all reads after writes so truncated address bits cannot pass.
    // Complemented addresses also cover the upper ceiling and carry paths.
    task address_walk;
        integer bit_number;
        reg [21:0] bit_addr;
        begin
            cpu_transfer(1, 22'h000000, 8'h47);
            cpu_transfer(1, 22'h3fffff, 8'h69);
            for (bit_number = 0; bit_number < 22; bit_number = bit_number + 1) begin
                bit_addr = 22'd1 << bit_number;
                cpu_transfer(1, bit_addr, 8'h80 + bit_number[7:0]);
                loader_transfer(1, ~bit_addr, 8'h40 + bit_number[7:0]);
            end
            loader_transfer(0, 22'h000000, 0);
            loader_transfer(0, 22'h3fffff, 0);
            for (bit_number = 0; bit_number < 22; bit_number = bit_number + 1) begin
                bit_addr = 22'd1 << bit_number;
                loader_transfer(0, bit_addr, 0);
                cpu_transfer(0, ~bit_addr, 0);
            end
        end
    endtask

    // Offer a CPU read on the very next edge after a CPU write accepted
    // alongside a loader read. Sweep the pair across the refresh boundary
    // so the latency measurement includes both queued work and refresh.
    task refresh_phase_sweep;
        integer phase_offset;
        integer ties_before;
        begin
            ties_before = both_accepted;
            for (phase_offset = 650; phase_offset < 670; phase_offset = phase_offset + 1) begin
                drain;
                @(posedge clk_sys);
                while (command != CMD_REFRESH)
                    @(posedge clk_sys);
                repeat (phase_offset) @(posedge clk_sys);
                fork
                    begin
                        @(negedge clk_sys);
                        cpu_mem_req = 1;
                        cpu_mem_we = 1;
                        cpu_mem_addr = 22'h040100;
                        cpu_mem_wdata = phase_offset[7:0];
                        @(posedge clk_sys);
                        while (!cpu_mem_accept)
                            @(posedge clk_sys);
                        @(negedge clk_sys);
                        cpu_mem_we = 0;
                        @(posedge clk_sys);
                        while (!cpu_mem_accept)
                            @(posedge clk_sys);
                        @(negedge clk_sys);
                        cpu_mem_req = 0;
                        @(posedge clk_sys);
                        while (!cpu_mem_rvalid)
                            @(posedge clk_sys);
                    end
                    loader_transfer(0, 22'h040100, 0);
                join
            end
            if (both_accepted == ties_before || max_cpu_req_latency <= max_cpu_accept_latency)
                $fatal(1, "Missing queued CPU read in refresh phase sweep");
        end
    endtask

    integer index;
    integer cpu_index, loader_index, idle_refreshes;
    reg [21:0] crossing;
    initial begin
        #1 rst_n = 0;
        repeat (4) @(negedge clk_sys);
        #1 rst_n = 1;
        // Both clients wait through initialization. The loader must see
        // the CPU write if both are accepted on the first available edge.
        fork
            cpu_transfer(1, 22'h030000, 8'ha6);
            loader_transfer(0, 22'h030000, 0);
        join
        if (both_accepted != 1)
            $fatal(1, "Missing simultaneous CPU/loader acceptance at initialization");

        // An older loader write must be visible to an overlapping CPU read.
        drain;
        loader_transfer(1, 22'h030001, 8'h3c);
        cpu_transfer(0, 22'h030001, 0);
        cpu_transfer(0, 22'h030000, 0);
        cpu_transfer(1, 22'h030000, 8'hf1);
        loader_transfer(0, 22'h030001, 0);

        // Continuous CPU writes use consecutive acceptance edges. A loader
        // request held throughout the stream must complete after it drains.
        drain;
        fork
            begin
                for (index = 0; index < 16; index = index + 1) begin
                    @(negedge clk_sys);
                    cpu_mem_req = 1;
                    cpu_mem_we = 1;
                    cpu_mem_addr = 22'h040100 + index[21:0];
                    cpu_mem_wdata = index[7:0] ^ 8'hb4;
                    @(posedge clk_sys);
                    while (!cpu_mem_accept)
                        @(posedge clk_sys);
                end
                @(negedge clk_sys);
                cpu_mem_req = 0;
                cpu_mem_we = 0;
            end
            begin
                @(negedge clk_sys);
                loader_transfer(1, 22'h040100, 8'h5f);
            end
        join
        if (consecutive_cpu == 0)
            $fatal(1, "Missing back-to-back CPU acceptance");
        for (index = 0; index < 16; index = index + 1)
            cpu_transfer(0, 22'h040100 + index[21:0], 0);

        address_walk;
        // A bank boundary at one row end, and the next row boundary.
        crossing = 22'd1 << (COL_BITS + 3);
        for (index = -4; index < 4; index = index + 1) begin
            loader_transfer(1, crossing + index[21:0], 8'hd0 ^ index[7:0]);
            loader_transfer(1, (crossing >> 2) + index[21:0], 8'hc0 ^ index[7:0]);
        end
        for (index = -4; index < 4; index = index + 1) begin
            cpu_transfer(0, crossing + index[21:0], 0);
            cpu_transfer(0, (crossing >> 2) + index[21:0], 0);
        end

        fill_screen(0);
        fill_screen(1);
        drain;
        scan_screens;
        read_through_commit(0, 13'd6911, 13'd6911, 8'h19);
        read_through_commit(1, 13'd0, 13'd0, 8'h74);
        read_through_commit(1, 13'd0, 13'd1, 8'h2a);
        // Just outside both screen ranges, wrong RAM bank, and addresses
        // with matching low bits in loader workspace or unallocated space.
        cpu_transfer(1, 22'h015b00, 8'hb1);
        loader_transfer(1, 22'h01db00, 8'hb2);
        loader_transfer(1, 22'h018000, 8'hb3);
        cpu_transfer(1, 22'h114000, 8'hb4);
        loader_transfer(1, 22'h11c000, 8'hb5);
        drain;
        scan_screens;
        if (forward_bank5 == 0 || forward_bank7 == 0 || different_byte == 0)
            $fatal(1, "Missing simultaneous screen read/commit coverage");

        loader_transfer(1, 22'h094800, 8'hbe);
        loader_transfer(1, 22'h094801, 8'hef);
        drain;
        stress = 1;
        fork
            begin
                for (cpu_index = 0; cpu_index < 1800; cpu_index = cpu_index + 1) begin
                    if (cpu_index % 7 == 0)
                        cpu_transfer(1, 22'h040100, cpu_index[7:0]);
                    cpu_transfer(0, 22'h040100 + {18'b0, cpu_index[3:0]}, 0);
                    if (cpu_index % 9 == 0)
                        repeat (cpu_index % 4) @(negedge clk_sys);
                end
            end
            begin
                for (loader_index = 0; loader_index < 1800; loader_index = loader_index + 1)
                    loader_transfer(loader_index[1], 22'h094800 + {21'b0, loader_index[0]},
                        loader_index[7:0]);
            end
        join
        drain;
        stress = 0;
        if (latency_reads != 1800 || refresh_under_load < 20 || refresh_with_cpu_waiting < 10)
            $fatal(1, "Insufficient refresh-under-load coverage, refresh=%0d CPU waiting=%0d",
                refresh_under_load, refresh_with_cpu_waiting);
        stress = 1;
        refresh_phase_sweep;
        drain;
        stress = 0;

        if (SMALL_SDRAM)
            check_small_chip_rows;
        drain;
        idle_refreshes = model.refresh_count;
        repeat (1400) begin
            @(negedge clk_sys);
            if (!mem_idle)
                $fatal(1, "Idle refresh falsely marks accepted work pending");
        end
        if (model.refresh_count <= idle_refreshes || accepted != issued ||
            writes + read_commands != accepted || responses != read_commands)
            $fatal(1, "Refresh or transaction accounting failed");

        $display("PASS: %0d MiB, %0d column bits, %0d writes, %0d reads, %0d operational refreshes",
            SMALL_SDRAM ? 4 : 32, COL_BITS, writes, responses, model.refresh_count);
        $display("Maximum refresh gap: %0d ps. Refreshes with CPU waiting during load: %0d",
            model.max_refresh_ps, refresh_with_cpu_waiting);
        $display("Worst CPU read latency under load and refresh alignment: %0d clocks from request, %0d from acceptance",
            max_cpu_req_latency, max_cpu_accept_latency);
        $finish;
    end

    initial begin
        #(64'd500000 * CLK_PS);
        $fatal(1, "Testbench watchdog expired");
    end
endmodule
