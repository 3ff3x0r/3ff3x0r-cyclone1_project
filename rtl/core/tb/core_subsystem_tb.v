`timescale 1ns/1ps

module core_subsystem_tb;
    reg clk_sys = 0;
    always #5 clk_sys = !clk_sys;
    reg rst_n = 0, cpu_reset_n = 0, guest_reset_n = 0, cpu_quiesce = 0;
    reg boot_overlay = 1, cfg_valid = 0;
    reg [2:0] cfg_timing_id = 0, cfg_paging_id = 0;
    reg [3:0] cfg_rom_valid_mask = 1;
    reg cfg_psg_enable = 0;
    reg [1:0] cfg_disk_kind = 0;
    wire cpu_quiesced, psg_ce;
    integer tick = 0;
    always @(negedge clk_sys) tick = tick + 1;
    wire ce_ula = tick % 12 == 0;
    wire ce_cpu = tick % 24 == 12;
    wire ce_psg = tick % 48 == 36;
    wire cpu_mem_req, cpu_mem_we;
    wire [21:0] cpu_mem_addr;
    wire [7:0] cpu_mem_wdata;
    reg cpu_mem_rvalid = 0;
    reg [7:0] cpu_mem_rdata;
    wire cpu_mem_deadline_miss;
    wire boot_bus_req, boot_bus_io, boot_bus_we;
    wire [15:0] boot_bus_addr;
    wire [7:0] boot_bus_wdata;
    wire screen_rd_req, screen_rd_bank7, ula_px_ce, ula_hs_n, ula_vs_n, ula_blank;
    wire [12:0] screen_rd_offset;
    reg screen_rd_valid = 0;
    reg [7:0] screen_rd_data = 0;
    wire [3:0] ula_color;
    wire [9:0] ula_x;
    wire [8:0] ula_y;
    wire mic_bit, beeper_bit, ay_req, disk_req, disk_we, disk_motor;
    wire [1:0] ay_op;
    wire [2:0] disk_reg;
    wire [7:0] ay_wdata, disk_wdata;
    reg [39:0] key_matrix_n = {40{1'b1}};
    reg [5:0] joy1 = 0, joy2 = 0;

    // The programs and signatures use distinct low 10-bit offsets per bank.
    reg [7:0] memory [0:12287];
    function integer location;
        input integer address;
        begin
            location = (address >> 14) * 1024 + (address & 1023);
        end
    endfunction
    reg [7:0] boot [0:31];
    reg [7:0] boot_data;
    always @* begin
        boot_data = 8'hff;
        if (boot_bus_addr < 32)
            boot_data = boot[boot_bus_addr];
    end
    wire boot_bus_ready = boot_bus_req && tick % 41 == 40;
    integer read_left = 0;
    integer latency = 0, accept_every = 1;
    reg block_writes = 0;
    wire cpu_mem_accept = tick % accept_every == 0 && read_left == 0 &&
                          !(block_writes && cpu_mem_we);
    integer pending_addr;
    reg outstanding = 0;
    reg waiting = 0;
    reg [30:0] held_mem;
    reg boot_waiting = 0;
    reg [25:0] held_boot;

    core_subsystem dut (
        .clk_sys(clk_sys), .rst_n(rst_n), .cpu_reset_n(cpu_reset_n),
        .guest_reset_n(guest_reset_n), .cpu_quiesce(cpu_quiesce), .cpu_quiesced(cpu_quiesced),
        .boot_overlay(boot_overlay), .cfg_valid(cfg_valid), .cfg_timing_id(cfg_timing_id),
        .cfg_paging_id(cfg_paging_id), .cfg_rom_valid_mask(cfg_rom_valid_mask),
        .cfg_psg_enable(cfg_psg_enable), .cfg_disk_kind(cfg_disk_kind),
        .cfg_input_map_id(2'd1), .cfg_joy1_b_map(2'd3), .cfg_joy2_b_map(2'd1),
        .ce_cpu(ce_cpu), .ce_ula(ce_ula), .ce_psg(ce_psg), .psg_ce(psg_ce),
        .mem_ready(1'b1), .cpu_mem_req(cpu_mem_req), .cpu_mem_accept(cpu_mem_accept),
        .cpu_mem_addr(cpu_mem_addr), .cpu_mem_we(cpu_mem_we), .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rvalid(cpu_mem_rvalid), .cpu_mem_rdata(cpu_mem_rdata),
        .cpu_mem_deadline_miss(cpu_mem_deadline_miss), .boot_bus_req(boot_bus_req),
        .boot_bus_io(boot_bus_io), .boot_bus_we(boot_bus_we), .boot_bus_addr(boot_bus_addr),
        .boot_bus_wdata(boot_bus_wdata), .boot_bus_ready(boot_bus_ready), .boot_bus_rdata(boot_data),
        .screen_rd_req(screen_rd_req), .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(screen_rd_offset), .screen_rd_valid(screen_rd_valid),
        .screen_rd_data(screen_rd_data), .ula_px_ce(ula_px_ce), .ula_color(ula_color),
        .ula_x(ula_x), .ula_y(ula_y), .ula_hs_n(ula_hs_n), .ula_vs_n(ula_vs_n),
        .ula_blank(ula_blank), .key_matrix_n(key_matrix_n), .joy1(joy1), .joy2(joy2),
        .ear_bit(1'b1), .mic_bit(mic_bit), .beeper_bit(beeper_bit),
        .ay_req(ay_req), .ay_op(ay_op), .ay_wdata(ay_wdata), .ay_rdata(8'h5c),
        .disk_req(disk_req), .disk_we(disk_we), .disk_reg(disk_reg), .disk_wdata(disk_wdata),
        .disk_rdata(8'h73), .disk_motor(disk_motor)
    );

    integer writes = 0, boot_writes = 0, boot_io = 0, reads = 0;
    integer ay_ops = 0, disk_ops = 0;
    integer valid_at_sample = 0;
    reg check_io = 0, previous_io = 0;
    integer early_x, last_x, slot_x, io_expected, io_waits, io_checks = 0, io_delayed = 0;
    integer slot;
    function integer ula_wait_at;
        input integer x;
        integer phase;
        begin
            phase = ((x - 46) / 2) % 8;
            ula_wait_at = x >= 46 && x < 302 && phase < 6 ? 6 - phase : 0;
        end
    endfunction

    always @(posedge clk_sys) begin
        if (!check_io) begin
            previous_io <= 0;
            io_checks = 0;
            io_delayed = 0;
        end else begin
            if (ce_cpu) begin
                early_x <= last_x;
                last_x <= ula_x;
            end
            if (dut.io_cycle && !previous_io) begin
                if (ula_y != 56) begin
                    $display("FAIL I/O fixture missed the first picture line");
                    $finish;
                end
                io_expected = 0;
                if (cfg_timing_id == 0) begin
                    if (dut.addr[15:14] == 2'b01)
                        io_expected = ula_wait_at(early_x);
                    slot_x = early_x + 2 * (1 + io_expected);
                    if (!dut.addr[0])
                        io_expected = io_expected + ula_wait_at(slot_x);
                    else if (dut.addr[15:14] == 2'b01)
                        for (slot = 0; slot < 3; slot = slot + 1) begin
                            io_expected = io_expected + ula_wait_at(slot_x);
                            slot_x = slot_x + 2 * (1 + ula_wait_at(slot_x));
                        end
                end
                io_waits = 0;
            end
            if (dut.io_cycle && ce_ula && !ce_cpu && !dut.cpu_ce_n)
                io_waits = io_waits + 1;
            if (dut.io_done) begin
                if (io_expected != io_waits) begin
                    $display("FAIL I/O wait count at port %h expected %d got %d", dut.addr, io_expected, io_waits);
                    $finish;
                end
                io_checks = io_checks + 1;
                if (io_waits != 0)
                    io_delayed = io_delayed + 1;
            end
            previous_io <= dut.io_cycle;
        end
    end

    reg first_guest_fetch = 0;
    always @(posedge clk_sys) begin
        screen_rd_valid <= screen_rd_req;
        if (screen_rd_req) begin
            if (screen_rd_offset >= 6912 || (boot_overlay && screen_rd_bank7)) begin
                $display("FAIL Screen mirror address or boot ownership");
                $finish;
            end
            screen_rd_data <= memory[location((screen_rd_bank7 ? 'h1c000 : 'h14000) + screen_rd_offset)];
        end
        if (waiting && (!cpu_mem_req || held_mem !== {cpu_mem_addr, cpu_mem_we, cpu_mem_wdata})) begin
            $display("FAIL Guest request changed under backpressure");
            $finish;
        end
        if (boot_waiting && (!boot_bus_req ||
                held_boot !== {boot_bus_io, boot_bus_we, boot_bus_addr, boot_bus_wdata})) begin
            $display("FAIL Boot request changed under backpressure");
            $finish;
        end
        waiting <= cpu_mem_req && !cpu_mem_accept;
        held_mem <= {cpu_mem_addr, cpu_mem_we, cpu_mem_wdata};
        boot_waiting <= boot_bus_req && !boot_bus_ready;
        held_boot <= {boot_bus_io, boot_bus_we, boot_bus_addr, boot_bus_wdata};
        if ((boot_overlay && cpu_mem_req) || (!boot_overlay && boot_bus_req)) begin
            $display("FAIL Bus ownership");
            $finish;
        end
        if (cpu_mem_we && !cpu_mem_req) begin
            $display("FAIL Idle guest write");
            $finish;
        end
        if (boot_bus_ready && boot_bus_we) begin
            if (boot_bus_wdata !== 8'ha7) begin
                $display("FAIL CPU boot data %h", boot_bus_wdata);
                $finish;
            end
            if (boot_bus_io) begin
                if (boot_bus_addr !== 16'ha710) begin
                    $display("FAIL CPU boot OUT address %h", boot_bus_addr);
                    $finish;
                end
                boot_io = boot_io + 1;
            end else begin
                if (boot_bus_addr !== 16'h4000) begin
                    $display("FAIL CPU boot memory address %h", boot_bus_addr);
                    $finish;
                end
                boot_writes = boot_writes + 1;
            end
        end
        if (ay_req) begin
            case (ay_ops)
                0: if (ay_op !== 0 || ay_wdata !== 8'h08) begin
                    $display("FAIL AY select");
                    $finish;
                end
                1: if (ay_op !== 1 || ay_wdata !== 8'h0f) begin
                    $display("FAIL AY write");
                    $finish;
                end
                2: if (ay_op !== 2) begin
                    $display("FAIL AY read");
                    $finish;
                end
                default: begin
                    $display("FAIL Unexpected AY operation");
                    $finish;
                end
            endcase
            ay_ops = ay_ops + 1;
        end
        if (disk_req) begin
            if (disk_we || disk_reg !== 0) begin
                $display("FAIL Unexpected disk I/O %b %d %h", disk_we, disk_reg, disk_wdata);
                $finish;
            end
            disk_ops = disk_ops + 1;
        end
        if (rst_n && (psg_ce !== (ce_psg && cfg_psg_enable && !boot_overlay && guest_reset_n))) begin
            $display("FAIL PSG cadence");
            $finish;
        end

        cpu_mem_rvalid <= 0;
        if (cpu_mem_rvalid) begin
            if (dut.mem_read_due && dut.cpu_ce_p)
                valid_at_sample = valid_at_sample + 1;
            if (!outstanding) begin
                $display("FAIL Read response without acceptance");
                $finish;
            end
            outstanding = 0;
        end
        if (read_left != 0) begin
            read_left <= read_left - 1;
            if (read_left == 1) begin
                cpu_mem_rvalid <= 1;
                cpu_mem_rdata <= memory[location(pending_addr)];
            end
        end
        if (cpu_mem_req && cpu_mem_accept) begin
            if (outstanding || cpu_mem_addr >= 196608) begin
                $display("FAIL Outstanding=%b address=%h write=%b", outstanding, cpu_mem_addr, cpu_mem_we);
                $finish;
            end
            if (first_guest_fetch) begin
                if (cpu_mem_addr !== 22'h20000 || cpu_mem_we) begin
                    $display("FAIL First guest fetch %h", cpu_mem_addr);
                    $finish;
                end
                first_guest_fetch = 0;
            end
            if (cpu_mem_we) begin
                if (cpu_mem_addr >= 22'h20000) begin
                    $display("FAIL Guest wrote a ROM");
                    $finish;
                end
                memory[location(cpu_mem_addr)] <= cpu_mem_wdata;
                writes = writes + 1;
            end else begin
                reads = reads + 1;
                outstanding = 1;
                if (latency == 0) begin
                    cpu_mem_rvalid <= 1;
                    cpu_mem_rdata <= memory[location(cpu_mem_addr)];
                end else begin
                    read_left <= latency;
                    pending_addr <= cpu_mem_addr;
                end
            end
        end
    end

    integer pc;
    task emit;
        input [7:0] b;
        begin
            memory[location(pc)] = b;
            pc = pc + 1;
        end
    endtask
    task ld_a;
        input [7:0] b;
        begin emit(8'h3e); emit(b); end
    endtask
    task store;
        input [15:0] a;
        begin emit(8'h32); emit(a[7:0]); emit(a[15:8]); end
    endtask
    task load;
        input [15:0] a;
        begin emit(8'h3a); emit(a[7:0]); emit(a[15:8]); end
    endtask
    task ld_bc;
        input [15:0] a;
        begin emit(8'h01); emit(a[7:0]); emit(a[15:8]); end
    endtask
    task port_write;
        input [15:0] a;
        input [7:0] b;
        begin ld_bc(a); ld_a(b); emit(8'hed); emit(8'h79); end
    endtask
    task port_read;
        input [15:0] a;
        begin ld_bc(a); emit(8'hed); emit(8'h78); end
    endtask
    task reset_guest;
        input [2:0] timing, paging;
        input [3:0] mask;
        begin
            @(negedge clk_sys);
            cpu_quiesce = 1;
            wait (cpu_quiesced);
            @(negedge clk_sys);
            cpu_reset_n = 0;
            guest_reset_n = 0;
            cfg_valid = 1;
            boot_overlay = 0;
            cfg_timing_id = timing;
            cfg_paging_id = paging;
            cfg_rom_valid_mask = mask;
            repeat (4) @(negedge clk_sys);
            cpu_quiesce = 0;
        end
    endtask
    task run_guest;
        begin
            @(negedge clk_sys);
            first_guest_fetch = 1;
            cpu_reset_n = 1;
            guest_reset_n = 1;
        end
    endtask
    task expect_byte;
        input integer a;
        input [7:0] value;
        begin
            if (memory[location(a)] !== value) begin
                $display("FAIL Byte %h expected %h got %h", a, value, memory[location(a)]);
                $finish;
            end
        end
    endtask

    integer i, mode, window, save_writes;
    integer phys_bank;
    reg [11:0] banks;
    initial begin
        for (i = 0; i < 12288; i = i + 1)
            memory[i] = i < 8192 ? 8'd0 : 8'h76;
        for (i = 0; i < 32; i = i + 1)
            boot[i] = 8'h76;
        // LD A,A7 / LD (4000),A / OUT (10),A / HALT.
        boot[0] = 'h3e; boot[1] = 'ha7;
        boot[2] = 'h32; boot[3] = 0; boot[4] = 'h40;
        boot[5] = 'hd3; boot[6] = 'h10;

        repeat (3) @(negedge clk_sys);
        rst_n = 1;
        cpu_reset_n = 1;
        wait (boot_io == 1);
        repeat (200) @(negedge clk_sys);
        if (boot_writes != 1 || boot_io != 1) begin
            $display("FAIL Boot bridge duplicated or lost a transfer");
            $finish;
        end

        reset_guest(0, 1, 1);
        pc = 'h20000;
        ld_a(19); emit(8'hc6); emit(23); store('h4000);
        load('h4000); store('h8000); store('h0000);
        port_read('hfcfe); store('hc000);
        port_read('hff1f); store('hc001);
        ld_a('h1d); emit(8'hd3); emit(8'hfe); emit(8'h76);
        key_matrix_n[0] = 0;
        key_matrix_n[6] = 0;
        joy1 = 6'b101001; // B, right, up
        latency = 20;
        accept_every = 7;
        run_guest;
        wait (mic_bit && beeper_bit);
        repeat (160) @(negedge clk_sys);
        expect_byte('h14000, 42);
        expect_byte('h08000, 42);
        expect_byte('h20000, 'h3e);
        expect_byte('h00000, 'hfc);
        expect_byte('h00001, 'h29);
        if (writes != 4 || cpu_mem_deadline_miss) begin
            $display("FAIL Delayed memory: writes=%0d deadline=%b", writes, cpu_mem_deadline_miss);
            $finish;
        end

        reset_guest(0, 0, 1);
        latency = 0;
        accept_every = 1;
        pc = 'h20000;
        ld_a('haa); store('h8000); store('hffff);
        load('h8000); store('h4001); emit(8'h76);
        run_guest;
        wait (writes == 5);
        @(negedge clk_sys);
        expect_byte('h14001, 'hff);
        expect_byte('h08000, 42);
        expect_byte('h03fff, 0);

        reset_guest(1, 2, 3);
        cfg_psg_enable = 1;
        pc = 'h20000;
        for (i = 0; i < 8; i = i + 1) begin
            port_write('h7ffd, i);
            store('hc004);
        end
        port_write('h7ffd, 'h3f); // ROM 1, bank 7, shadow and lock
        pc = pc + 'h4000;
        port_write('h7ffd, 0);
        ld_a('ha6); store('hc005);
        port_write('hfffd, 8);
        port_write('hbffd, 15);
        port_read('hfffd); store('hc006); emit(8'h76);
        run_guest;
        wait (ay_ops == 3);
        repeat (400) @(negedge clk_sys);
        for (i = 0; i < 8; i = i + 1)
            expect_byte(i * 16384 + 4, i);
        expect_byte('h1c005, 'ha6);
        expect_byte('h1c006, 'h5c);
        if (!screen_rd_bank7) begin
            $display("FAIL Shadow screen was not selected");
            $finish;
        end

        for (mode = 0; mode < 4; mode = mode + 1) begin
            reset_guest(2, 3, 15);
            cfg_psg_enable = 0;
            cfg_disk_kind = 1;
            pc = 'h20000;
            port_read('h2ffd); store('h7f01);
            port_write('h1ffd, 9 + 2 * mode);
            case (mode)
                0: banks = {3'd3, 3'd2, 3'd1, 3'd0};
                1: banks = {3'd7, 3'd6, 3'd5, 3'd4};
                2: banks = {3'd3, 3'd6, 3'd5, 3'd4};
                3: banks = {3'd3, 3'd6, 3'd7, 3'd4};
            endcase
            // Place code in each of the four mapped windows, so each
            // window tests an opcode fetch as well as a write.
            save_writes = writes;
            for (window = 0; window < 4; window = window + 1) begin
                phys_bank = banks[3 * window +: 3];
                pc = phys_bank * 16384 + (window == 0 ? (pc & 'h3fff) : 'h100);
                ld_a('h80 + 4 * mode + window);
                store(window * 16384 + 'h3f00);
                if (window < 3) begin
                    emit('hc3); emit(0); emit('h41 + 64 * window);
                end else
                    emit('h76);
            end
            run_guest;
            wait (writes == save_writes + 5);
            repeat (200) @(negedge clk_sys);
            for (window = 0; window < 4; window = window + 1)
                expect_byte(banks[3 * window +: 3] * 16384 + 'h3f00, 'h80 + 4 * mode + window);
            expect_byte('h17f01, 'h73);
            if (!disk_motor || disk_ops != mode + 1) begin
                $display("FAIL Disk status or motor decode");
                $finish;
            end
        end

        reset_guest(2, 3, 11);
        cfg_disk_kind = 0;
        pc = 'h20000;
        emit('hc3); emit(0); emit('h80);
        pc = 'h08000;
        port_write('h1ffd, 4);
        load('h0200); store('h7f06); // ROM 2 is masked out.
        port_write('h7ffd, 'h30);  // ROM 3, lock paging.
        port_write('h1ffd, 0);
        port_write('h7ffd, 0);
        load('h0200); store('h7f07); emit('h76);
        memory[location('h28200)] = 'h68;
        memory[location('h2c200)] = 'he4;
        run_guest;
        wait (memory[location('h17f07)] == 'he4);
        expect_byte('h17f06, 'hff);

        reset_guest(5, 4, 7);
        cfg_disk_kind = 2;
        pc = 'h20000;
        port_write('h7ffd, 'h10);
        pc = pc + 'h4000;
        emit('hc3); emit(0); emit('h3d);
        pc = 'h2bd00;
        port_read('h001f); store('h7f02);
        emit('hc3); emit(0); emit('h40);
        pc = 'h14000;
        emit('hc3); emit('h00); emit('h10);
        pc = 'h25000;
        ld_a('hc5); store('h7f03); emit('h76);
        run_guest;
        wait (memory[location('h17f03)] == 'hc5);
        expect_byte('h17f02, 'h73);
        if (disk_ops != 5 || cpu_mem_deadline_miss) begin
            $display("FAIL Beta overlay or normal deadline check");
            $finish;
        end

        reset_guest(3, 1, 1);
        cfg_disk_kind = 0;
        pc = 'h20000;
        port_read('hfffe); store('h7f04); emit('h76);
        run_guest;
        wait (memory[location('h17f04)] == 'h7f);

        for (mode = 0; mode < 2; mode = mode + 1) begin
            reset_guest(mode == 0 ? 0 : 2, mode == 0 ? 1 : 3, 15);
            pc = 'h20000;
            port_write('h40fe, 8'h1a);
            port_write('h40ff, 8'h1b);
            port_write('h00fe, 8'h1c);
            port_write('h00ff, 8'h1d);
            emit('h76);
            @(negedge clk_sys);
            guest_reset_n = 1;
            wait (ula_y == 56);
            check_io = 1;
            run_guest;
            wait (io_checks == 4);
            @(negedge clk_sys);
            if (mode == 0 ? (io_delayed == 0) : (io_delayed != 0)) begin
                $display("FAIL I/O contention coverage for mode %0d", mode);
                $finish;
            end
            check_io = 0;
        end

        reset_guest(0, 1, 1);
        pc = 'h20000;
        ld_a('h42); store('h4000);
        emit('hdd); emit('h21); emit(0); emit('h40); // LD IX,4000
        emit('hdd); emit('hcb); emit(0); emit('h06); // RLC (IX+0)
        load('h4000); store('h7f08); emit('h76);
        latency = 34;
        run_guest;
        wait (memory[location('h17f08)] == 'h84);
        if (cpu_mem_deadline_miss || valid_at_sample < 10) begin
            $display("FAIL Exact sample-edge response was not bypassed");
            $finish;
        end

        reset_guest(0, 1, 1);
        pc = 'h20000;
        ld_a('hdb); store('h7f05); emit('h76);
        // Intentionally miss the fetch deadline. The CPU must retry
        // its sample, and the unmodified request must complete once.
        latency = 45;
        block_writes = 1;
        run_guest;
        wait (cpu_mem_we && cpu_mem_addr == 'h17f05);
        repeat (70) @(negedge clk_sys);
        block_writes = 0;
        wait (memory[location('h17f05)] == 'hdb);
        if (!cpu_mem_deadline_miss) begin
            $display("FAIL Expected deadline diagnostic after excess latency");
            $finish;
        end

        $display("PASS boot, paging, ports, I/O contention and memory (%0d reads, %0d on the sample edge)",
                 reads, valid_at_sample);
        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL Timeout tick=%0d CPU=%h writes=%d boot=%d/%d paging=%d deadline=%b",
                 tick, dut.addr, writes, boot_writes, boot_io, cfg_paging_id, cpu_mem_deadline_miss);
        $finish;
    end
endmodule
