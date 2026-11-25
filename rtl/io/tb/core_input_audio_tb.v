`timescale 1ns/1ps

module core_input_audio_tb;
    reg clk_sys = 0;
    always #5.820 clk_sys = !clk_sys;
    reg rst_n = 0, guest_reset_n = 0;
    reg [1:0] cfg_input_map_id = 0, cfg_joy1_b_map = 1;
    localparam [1:0] CFG_JOY2_B_MAP = 2;
    reg cfg_psg_enable = 1;
    wire ce_cpu, ce_ula, ce_psg, psg_ce, clocks_ready;
    reg ps2_clk = 1, ps2_data = 1;
    reg [5:0] joy1_n = 6'h3f, joy2_n = 6'h3f;
    wire [39:0] key_matrix_n;
    wire [5:0] joy1, joy2;
    wire mic_bit, beeper_bit, ay_req, ear_bit, mic_out;
    wire [1:0] ay_op;
    wire [7:0] ay_wdata, ay_rdata;
    wire [5:0] audio_l, audio_r;
    reg mic_record = 0, tap_ear_valid = 1;
    wire cpu_mem_req, cpu_mem_we, cpu_mem_deadline_miss;
    wire [21:0] cpu_mem_addr;
    wire [7:0] cpu_mem_wdata;
    reg cpu_mem_rvalid = 0;
    reg [7:0] cpu_mem_rdata = 0;
    wire screen_rd_req;
    reg screen_read_sampled = 0, screen_rd_valid = 0;

    video_clock_enables clocks (
        .clk_sys(clk_sys), .rst_n(rst_n), .cfg_timing_id(3'd1),
        .cfg_psg_enable(cfg_psg_enable), .ce_cpu(ce_cpu), .ce_ula(ce_ula),
        .ce_psg(ce_psg), .clocks_ready(clocks_ready)
    );
    input_subsystem inputs (
        .clk_sys(clk_sys), .rst_n(rst_n), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .joy1_n(joy1_n), .joy2_n(joy2_n), .key_matrix_n(key_matrix_n),
        .joy1(joy1), .joy2(joy2), .soft_reset_key(), .recovery_key(),
        .tap_play_toggle(), .tap_rewind()
    );
    audio_subsystem audio (
        .clk_sys(clk_sys), .rst_n(rst_n), .guest_reset_n(guest_reset_n),
        .cfg_psg_enable(cfg_psg_enable), .ce_psg(psg_ce), .ay_req(ay_req),
        .ay_op(ay_op), .ay_wdata(ay_wdata), .ay_rdata(ay_rdata), .beeper_bit(beeper_bit),
        .mic_bit(mic_bit), .mic_record(mic_record), .mic_out(mic_out),
        .ear_idle_bit(1'b1), .tap_ear_valid(tap_ear_valid), .tap_ear_bit(1'b0),
        .ear_bit(ear_bit), .audio_l(audio_l), .audio_r(audio_r)
    );
`ifdef REGISTERED_CPU_CLOCK
    wire clk_cpu;
    cpu_clock_model #(.FABRIC_PERIOD_PS(11640)) cpu_clock (clk_cpu);
`endif
    core_subsystem core (
`ifdef REGISTERED_CPU_CLOCK
        .clk_cpu(clk_cpu),
`endif
        .clk_sys(clk_sys), .rst_n(rst_n), .cpu_reset_n(guest_reset_n),
        .guest_reset_n(guest_reset_n), .cpu_quiesce(1'b0), .cpu_quiesced(),
        .boot_overlay(1'b0), .cfg_valid(1'b1), .cfg_timing_id(3'd1), .cfg_paging_id(3'd2),
        .cfg_rom_valid_mask(4'b0011), .cfg_psg_enable(cfg_psg_enable), .cfg_disk_kind(2'd0),
        .cfg_input_map_id(cfg_input_map_id), .cfg_joy1_b_map(cfg_joy1_b_map),
        .cfg_joy2_b_map(CFG_JOY2_B_MAP), .ce_cpu(ce_cpu), .ce_ula(ce_ula), .ce_psg(ce_psg),
        .psg_ce(psg_ce), .mem_ready(1'b1), .cpu_mem_req(cpu_mem_req),
        .cpu_mem_accept(1'b1), .cpu_mem_addr(cpu_mem_addr), .cpu_mem_we(cpu_mem_we),
        .cpu_mem_wdata(cpu_mem_wdata), .cpu_mem_rvalid(cpu_mem_rvalid),
        .cpu_mem_rdata(cpu_mem_rdata), .cpu_mem_deadline_miss(cpu_mem_deadline_miss),
        .boot_bus_req(), .boot_bus_io(), .boot_bus_we(), .boot_bus_addr(), .boot_bus_wdata(),
        .boot_bus_ready(1'b0), .boot_bus_rdata(8'hff),
        .screen_rd_req(screen_rd_req), .screen_rd_bank7(), .screen_rd_offset(),
        .screen_rd_valid(screen_rd_valid), .screen_rd_data(8'd0), .ula_px_ce(),
        .ula_color(), .ula_x(), .ula_y(), .ula_hs_n(), .ula_vs_n(), .ula_blank(),
        .key_matrix_n(key_matrix_n), .joy1(joy1), .joy2(joy2), .ear_bit(ear_bit),
        .mic_bit(mic_bit), .beeper_bit(beeper_bit), .ay_req(ay_req), .ay_op(ay_op),
        .ay_wdata(ay_wdata), .ay_rdata(ay_rdata), .disk_req(), .disk_we(), .disk_reg(),
        .disk_wdata(), .disk_rdata(8'hff), .disk_motor()
    );

    reg [7:0] rom [0:127];
    reg [7:0] signature [0:7];
    integer writes = 0, ay_cycles = 0, cpu_ticks = 0, last_psg_cpu_tick = 0;
    always @(posedge clk_sys) begin
        screen_read_sampled <= screen_rd_req;
        screen_rd_valid <= screen_read_sampled;
        cpu_mem_rvalid <= cpu_mem_req && !cpu_mem_we;
        if (cpu_mem_req && !cpu_mem_we)
            cpu_mem_rdata <= (cpu_mem_addr >= 22'h020000 && cpu_mem_addr < 22'h020080) ?
                             rom[cpu_mem_addr[6:0]] : 8'hff;
        if (cpu_mem_req && cpu_mem_we) begin
            if (cpu_mem_addr !== 22'h008000 + writes || writes >= 8) begin
                $display("FAIL CPU signature write %h at index %d", cpu_mem_addr, writes);
                $finish;
            end
            signature[writes] <= cpu_mem_wdata;
            writes = writes + 1;
        end
        if (ay_req)
            ay_cycles = ay_cycles + 1;
        if (ce_cpu)
            cpu_ticks = cpu_ticks + 1;
        if (ce_psg) begin
            if (!ce_cpu || !ce_ula ||
                (last_psg_cpu_tick != 0 && cpu_ticks-last_psg_cpu_tick != 2)) begin
                $display("FAIL D PSG cadence");
                $finish;
            end
            last_psg_cpu_tick = cpu_ticks;
        end
        if (psg_ce !== (ce_psg && guest_reset_n && cfg_psg_enable)) begin
            $display("FAIL C to F PSG enable gating");
            $finish;
        end
    end

    task ps2_bit;
        input value;
        begin
            ps2_data = value;
            repeat (18) @(negedge clk_sys);
            ps2_clk = 0;
            repeat (31) @(negedge clk_sys);
            ps2_clk = 1;
            repeat (11) @(negedge clk_sys);
        end
    endtask
    task send;
        input [7:0] value;
        integer bit_number;
        begin
            ps2_bit(0);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1)
                ps2_bit(value[bit_number]);
            ps2_bit(~^value);
            ps2_bit(1);
        end
    endtask

    integer pc = 0;
    task emit;
        input [7:0] opcode;
        begin rom[pc] = opcode; pc = pc + 1; end
    endtask
    task port_read_store;
        input [15:0] port_address, ram_address;
        begin
            emit(8'h01); emit(port_address[7:0]); emit(port_address[15:8]); // LD BC, port
            emit(8'hed); emit(8'h78); // IN A,(C)
            emit(8'h32); emit(ram_address[7:0]); emit(ram_address[15:8]); // LD (ram), A
        end
    endtask
    task port_write;
        input [15:0] port_address;
        input [7:0] value;
        begin
            emit(8'h01); emit(port_address[7:0]); emit(port_address[15:8]); // LD BC, port
            emit(8'h3e); emit(value); // LD A, value
            emit(8'hed); emit(8'h79); // OUT (C), A
        end
    endtask
    task expect_signature;
        input [63:0] expected;
        integer index;
        begin
            for (index = 0; index < 8; index = index + 1)
                if (signature[index] !== expected[8*index +: 8]) begin
                    $display("FAIL CPU signature byte %d got %h expected %h", index,
                              signature[index], expected[8*index +: 8]);
                    $finish;
                end
            if (cpu_mem_deadline_miss || ay_cycles != 5 || !mic_out || !mic_bit ||
                !beeper_bit || {audio_l, audio_r} !== {6'd47, 6'd32}) begin
                $display("FAIL CPU FE outputs or AY transfer count=%d L/R=%d/%d",
                          ay_cycles, audio_l, audio_r);
                $finish;
            end
        end
    endtask

    initial begin
        // An original Z80 diagnostic. It reads FE and Kempston, writes FE
        // and AY, then stores the results the CPU actually sampled.
        port_read_store(16'heffe, 16'h8000);
        port_read_store(16'hf7fe, 16'h8001);
        port_read_store(16'h7ffe, 16'h8002);
        port_read_store(16'heefe, 16'h8003);
        port_read_store(16'hfffe, 16'h8004);
        port_read_store(16'hff1f, 16'h8005);
        port_write(16'hfffe, 8'h18);
        port_write(16'hfffd, 7);
        port_write(16'hbffd, 8'h3f);
        port_write(16'hfffd, 8);
        port_write(16'hbffd, 8'hef);
        port_read_store(16'hfffd, 16'h8006);
        port_read_store(16'hfffe, 16'h8007);
        emit(8'h76); // HALT

        repeat (4) @(negedge clk_sys);
        rst_n = 1;
        repeat (21500) @(negedge clk_sys);
        if (!clocks_ready || psg_ce) begin
            $display("FAIL clocks ready during guest reset");
            $finish;
        end
        send(8'h22); send(8'h45); // X and 0
        joy1_n = ~6'b110101; // B, A, left, up
        joy2_n = ~6'b111010; // B, A, right, down
        repeat (4) @(negedge clk_sys);
        guest_reset_n = 1;
        wait (writes == 8);
        repeat (40) @(negedge clk_sys);
        expect_signature(64'hbf0fffbfa8bca9ac);

        mic_record = 1;
        repeat (4) @(negedge clk_sys);
        if ({audio_l, audio_r} !== {6'd63, 6'd32}) begin
            $display("FAIL clean MIC on left DAC from CPU FE write");
            $finish;
        end
        mic_record = 0;
        guest_reset_n = 0;
        cfg_input_map_id = 1;
        cfg_joy1_b_map = 3;
        tap_ear_valid = 0;
        writes = 0;
        ay_cycles = 0;
        send(8'hf0); send(8'h45); // Release 0 while the guest is held.
        if (key_matrix_n !== ~40'h4 || !ear_bit || mic_out || psg_ce) begin
            $display("FAIL guest reset input/tape continuity");
            $finish;
        end
        guest_reset_n = 1;
        wait (writes == 8);
        repeat (40) @(negedge clk_sys);
        expect_signature(64'hff0f3afffbfde9ff);

        $display("PASS real T80, Ticket C FE/AY/Kempston, Ticket D clock enables and Ticket F");
        $finish;
    end

    initial begin
        repeat (80000) @(posedge clk_sys);
        $display("FAIL real core integration timeout");
        $finish;
    end
endmodule
