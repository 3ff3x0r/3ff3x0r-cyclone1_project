`timescale 1ns/1ps

module audio_subsystem_tb;
    reg clk_sys = 0;
    always #5 clk_sys = !clk_sys;
    reg rst_n = 0, guest_reset_n = 0, cfg_psg_enable = 1, ce_psg = 0;
    reg ay_req = 0;
    reg [1:0] ay_op = 0;
    reg [7:0] ay_wdata = 0;
    wire [7:0] ay_rdata;
    reg beeper_bit = 0, mic_bit = 0, mic_record = 0;
    wire mic_out;
    reg ear_idle_bit = 0, tap_ear_valid = 0, tap_ear_bit = 0;
    wire ear_bit;
    wire [5:0] audio_l, audio_r;

    audio_subsystem dut (
        .clk_sys(clk_sys), .rst_n(rst_n), .guest_reset_n(guest_reset_n),
        .cfg_psg_enable(cfg_psg_enable), .ce_psg(ce_psg),
        .ay_req(ay_req), .ay_op(ay_op), .ay_wdata(ay_wdata), .ay_rdata(ay_rdata),
        .beeper_bit(beeper_bit), .mic_bit(mic_bit), .mic_record(mic_record), .mic_out(mic_out),
        .ear_idle_bit(ear_idle_bit), .tap_ear_valid(tap_ear_valid), .tap_ear_bit(tap_ear_bit),
        .ear_bit(ear_bit), .audio_l(audio_l), .audio_r(audio_r)
    );

    task reset_guest;
        begin
            guest_reset_n = 0;
            repeat (2) @(negedge clk_sys);
            if ({audio_l, audio_r, mic_out} !== 0 || ay_rdata !== 8'hff) begin
                $display("FAIL guest audio reset");
                $finish;
            end
            guest_reset_n = 1;
        end
    endtask

    task ay_cycle;
        input [1:0] op;
        input [7:0] data;
        begin
            ay_op = op;
            ay_wdata = data;
            ay_req = 1;
            @(negedge clk_sys);
            ay_req = 0;
            // C may sample readback before asserting an end-of-cycle request.
            @(negedge clk_sys);
        end
    endtask

    task write_register;
        input [7:0] address, value;
        begin ay_cycle(0, address); ay_cycle(1, value); end
    endtask

    task expect_register;
        input [7:0] address, value;
        begin
            ay_cycle(0, address);
            if (ay_rdata !== value) begin
                $display("FAIL AY register %h read %h expected %h", address, ay_rdata, value);
                $finish;
            end
            ay_cycle(2, 0);
            if (ay_rdata !== value) begin
                $display("FAIL AY read operation altered selected register");
                $finish;
            end
        end
    endtask

    task tick;
        begin
            ce_psg = 1;
            @(negedge clk_sys);
            ce_psg = 0;
            repeat (2) @(negedge clk_sys);
        end
    endtask

    task expect_mix;
        input [5:0] left, right;
        begin
            repeat (2) @(negedge clk_sys);
            if (audio_l !== left || audio_r !== right) begin
                $display("FAIL DAC L/R %d/%d expected %d/%d", audio_l, audio_r, left, right);
                $finish;
            end
        end
    endtask

    // AY fixed-volume reference, also checked against each envelope step.
    localparam [127:0] AY_LEVELS = 128'hffd7b590725b412822150f0a06040300;
    localparam [127:0] REG_MASKS = 128'hffff0fffff1f1f1fff1f0fff0fff0fff;
    localparam [39:0] NOISE_BITS = 40'b1000000000000000010000000000000100100000;
    function integer envelope_level;
        input integer shape_number, step_number;
        integer phase;
        begin
            phase = step_number % 16;
            case (shape_number)
                0, 1, 2, 3, 9: envelope_level = step_number < 16 ? 15-phase : 0;
                4, 5, 6, 7, 15: envelope_level = step_number < 16 ? phase : 0;
                8: envelope_level = 15-phase;
                10: envelope_level = (step_number/16) % 2 == 0 ? 15-phase : phase;
                11: envelope_level = step_number < 16 ? 15-phase : 15;
                12: envelope_level = phase;
                13: envelope_level = step_number < 16 ? phase : 15;
                14: envelope_level = (step_number/16) % 2 == 0 ? phase : 15-phase;
                default: envelope_level = 0;
            endcase
        end
    endfunction

    task expect_level_a;
        input integer expected;
        begin
            if (dut.psg_a !== AY_LEVELS[8*expected +: 8]) begin
                $display("FAIL channel A %d expected level %d (%d) at %t",
                          dut.psg_a, expected, AY_LEVELS[8*expected +: 8], $time);
                $finish;
            end
        end
    endtask

    integer index, pulse, shape, old_a, edge_a, edge_b, count_a, count_b;
    reg [7:0] prev_a, prev_b;
    initial begin
        repeat (3) @(negedge clk_sys);
        rst_n = 1;
        reset_guest;
        expect_mix(0, 0);

        for (index = 0; index < 16; index = index + 1) begin
            write_register(index[7:0], 8'hff);
            expect_register(index[7:0], REG_MASKS[index*8 +: 8]);
        end
        write_register(7, 0); // Both I/O latches in input mode
        write_register(14, 8'h25); expect_register(14, 8'hff);
        write_register(15, 8'h5e); expect_register(15, 8'hff);
        write_register(7, 8'h40); expect_register(14, 8'h25); expect_register(15, 8'hff);
        write_register(7, 8'h80); expect_register(14, 8'hff); expect_register(15, 8'h5e);
        write_register(7, 8'hc0); expect_register(14, 8'h25); expect_register(15, 8'h5e);
        write_register(8'h14, 8'h00); expect_register(8'h14, 8'hff);
        expect_register(4, 8'hff);
        ay_cycle(3, 8'h00); expect_register(4, 8'hff);

        reset_guest;
        write_register(7, 8'h3f);
        for (index = 0; index < 16; index = index + 1) begin
            write_register(8, index[7:0]);
            tick;
            expect_level_a(index);
        end
        expect_mix(15, 0);
        write_register(8, 0);
        expect_level_a(15); // Writes take effect on the next PSG sample edge.
        tick;
        expect_mix(0, 0);

        reset_guest;
        write_register(0, 3); // Period A = 16 * 3, B = 16 * 2, C = 16 * 0-as-1
        write_register(2, 2);
        write_register(7, 8'h38); // Tone only
        write_register(8, 15); write_register(9, 15); write_register(10, 15);
        edge_a = 0; edge_b = 0; count_a = 0; count_b = 0;
        prev_a = 0; prev_b = 0;
        for (pulse = 1; pulse <= 129; pulse = pulse + 1) begin
            tick;
            if (dut.psg_a !== prev_a) begin
                if (pulse-edge_a !== (count_a == 0 ? 25 : 24)) begin
                    $display("FAIL tone A interval %d", pulse-edge_a);
                    $finish;
                end
                edge_a = pulse;
                count_a = count_a + 1;
            end
            if (dut.psg_b !== prev_b) begin
                if (pulse-edge_b !== (count_b == 0 ? 17 : 16)) begin
                    $display("FAIL tone B interval %d", pulse-edge_b);
                    $finish;
                end
                edge_b = pulse;
                count_b = count_b + 1;
            end
            if (dut.psg_c !== ((pulse-1)/8 % 2 == 1 ? 8'hff : 8'h00)) begin
                $display("FAIL tone C zero-period behavior");
                $finish;
            end
            prev_a = dut.psg_a;
            prev_b = dut.psg_b;
        end
        if (count_a != 5 || count_b != 8) begin
            $display("FAIL missing tone edges");
            $finish;
        end
        $display("PASS measured AY tone periods of 48, 32 and 16 PSG-enable ticks");

        for (index = 0; index <= 2; index = index + 2) begin
            reset_guest;
            write_register(6, index[7:0]);
            write_register(7, 8'h37); // Only noise gates channel A.
            write_register(8, 15);
            for (pulse = 1; pulse <= (index == 0 ? 640 : 1280); pulse = pulse + 1) begin
                tick;
                expect_level_a(NOISE_BITS[39 - (pulse-1)/(index == 0 ? 16 : 32)] ? 15 : 0);
            end
        end

        reset_guest;
        write_register(7, 8'h3f); write_register(8, 16);
        write_register(11, 1);
        for (shape = 0; shape < 16; shape = shape + 1) begin
            write_register(13, shape[7:0]);
            for (pulse = 1; pulse <= 560; pulse = pulse + 1) begin
                tick;
                expect_level_a(envelope_level(shape, (pulse-1)/16));
            end
        end

        write_register(11, 0); write_register(13, 8'h0c);
        for (pulse = 1; pulse <= 20; pulse = pulse + 1) begin
            tick;
            expect_level_a((pulse-1)/8);
        end
        write_register(13, 8'h0c); // Same shape restarts part-way through a step.
        for (pulse = 1; pulse <= 13; pulse = pulse + 1) begin
            tick;
            expect_level_a((pulse-1)/8);
        end
        old_a = dut.psg_a;
        cfg_psg_enable = 0;
        write_register(13, 8'h09);
        repeat (32) tick;
        expect_level_a(0);
        if (ay_rdata !== 8'hff) begin
            $display("FAIL disabled AY read");
            $finish;
        end
        beeper_bit = 1;
        expect_mix(32, 32);
        cfg_psg_enable = 1;
        expect_register(13, 8'h0c);
        tick;
        if (dut.psg_a !== old_a[7:0]) begin
            $display("FAIL disabled AY advanced its phase");
            $finish;
        end

        write_register(8, 15); write_register(9, 15); write_register(10, 15);
        tick;
        expect_mix(63, 63);
        beeper_bit = 0;
        expect_mix(31, 31);
        mic_bit = 1; // MIC is independent of the normal monitor mix.
        expect_mix(31, 31);
        if (mic_out !== 1) begin
            $display("FAIL clean digital MIC output");
            $finish;
        end
        mic_record = 1;
        expect_mix(63, 31);
        mic_bit = 0;
        expect_mix(0, 31);
        if (mic_out !== 0) begin
            $display("FAIL digital MIC low");
            $finish;
        end

        #1;
        if (ear_bit !== 0) begin $display("FAIL EAR idle low"); $finish; end
        ear_idle_bit = 1;
        #1;
        if (ear_bit !== 1) begin $display("FAIL EAR idle high"); $finish; end
        tap_ear_valid = 1;
        #1;
        if (ear_bit !== 0) begin $display("FAIL valid TAP EAR low"); $finish; end
        tap_ear_bit = 1; ear_idle_bit = 0;
        #1;
        if (ear_bit !== 1) begin $display("FAIL valid TAP EAR high"); $finish; end
        tap_ear_valid = 0;
        #1;
        if (ear_bit !== 0) begin $display("FAIL EAR return to idle"); $finish; end
        @(negedge clk_sys);
        reset_guest;
        expect_register(8, 0);
        expect_mix(0, 0);
        $display("PASS AY masks, I/O, noise, envelopes, profile mute, DAC, MIC and EAR");
        $finish;
    end
endmodule
