`timescale 1ns/1ps

module input_subsystem_tb;
    reg clk_sys = 0;
    always #500 clk_sys = !clk_sys;
    reg rst_n = 0;
    reg ps2_clk = 1, ps2_data = 1;
    reg [5:0] joy1_n = 6'h3f, joy2_n = 6'h3f;
    wire [39:0] key_matrix_n;
    wire [5:0] joy1, joy2;
    wire soft_reset_key, recovery_key, tap_play_toggle, tap_rewind;
    reg [1:0] input_map = 0, b1_map = 1, b2_map = 1;
    integer toggles = 0, rewinds = 0;

    input_subsystem #(.CLK_SYS_HZ(1000000)) dut (
        .clk_sys(clk_sys), .rst_n(rst_n), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .joy1_n(joy1_n), .joy2_n(joy2_n), .key_matrix_n(key_matrix_n),
        .joy1(joy1), .joy2(joy2), .soft_reset_key(soft_reset_key),
        .recovery_key(recovery_key), .tap_play_toggle(tap_play_toggle), .tap_rewind(tap_rewind)
    );

    always @(posedge clk_sys) begin
        if (tap_play_toggle) toggles = toggles + 1;
        if (tap_rewind) rewinds = rewinds + 1;
    end

    // Independent consumer derived from the interface contract. The separate
    // integration fixture runs the same ports through the actual machine core.
    function [4:0] fe_keys;
        input [7:0] row_n;
        reg [39:0] held;
        integer row;
        begin
            held = ~key_matrix_n;
            if (input_map < 2) begin
                if (input_map == 0) begin
                    if (joy1[0]) held[21] = 1; // P1 up = 9
                    if (joy1[1]) held[22] = 1; // down = 8
                    if (joy1[2]) held[24] = 1; // left = 6
                    if (joy1[3]) held[23] = 1; // right = 7
                    if (joy1[4]) held[20] = 1; // fire = 0
                end
                if (joy2[0]) held[18] = 1; // P2 up = 4
                if (joy2[1]) held[17] = 1; // down = 3
                if (joy2[2]) held[15] = 1; // left = 1
                if (joy2[3]) held[16] = 1; // right = 2
                if (joy2[4]) held[19] = 1; // fire = 5
                if (joy1[5] && b1_map == 1) held[35] = 1;
                if (joy2[5] && b2_map == 1) held[35] = 1;
                if (joy1[5] && b1_map == 2) held[36] = 1;
                if (joy2[5] && b2_map == 2) held[36] = 1;
            end
            fe_keys = 5'h1f;
            for (row = 0; row < 8; row = row + 1)
                if (!row_n[row])
                    fe_keys = fe_keys & ~held[5*row +: 5];
        end
    endfunction

    wire [7:0] kempston = input_map == 1 ?
        {2'b00, b1_map == 3 && joy1[5], joy1[4], joy1[0], joy1[1], joy1[2], joy1[3]} : 8'hff;

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

    task frame;
        input [7:0] value;
        input start, bad_parity, stop;
        integer bit_number;
        begin
            ps2_bit(start);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1)
                ps2_bit(value[bit_number]);
            ps2_bit((~^value) ^ bad_parity);
            ps2_bit(stop);
            ps2_data = 1;
        end
    endtask

    task send;
        input [7:0] value;
        begin frame(value, 1'b0, 1'b0, 1'b1); end
    endtask

    task release_key;
        input [7:0] value;
        begin send(8'hf0); send(value); end
    endtask

    task expect_keys;
        input [39:0] pressed;
        begin
            if (key_matrix_n !== ~pressed) begin
                $display("FAIL matrix pressed=%h expected=%h at %t", ~key_matrix_n, pressed, $time);
                $finish;
            end
        end
    endtask

    task expect_joysticks;
        input [5:0] p1, p2;
        input [4:0] row3, row4, row7;
        input [7:0] kemp;
        begin
            repeat (4) @(negedge clk_sys);
            if (joy1 !== p1 || joy2 !== p2 || fe_keys(8'hf7) !== row3 ||
                fe_keys(8'hef) !== row4 || fe_keys(8'h7f) !== row7 || kempston !== kemp) begin
                $display("FAIL sticks %h/%h rows %h/%h/%h Kempston %h at %t",
                          joy1, joy2, fe_keys(8'hf7), fe_keys(8'hef), fe_keys(8'h7f), kempston, $time);
                $finish;
            end
        end
    endtask

    localparam [319:0] MATRIX_CODES = {
        8'h12, 8'h1a, 8'h22, 8'h21, 8'h2a,
        8'h1c, 8'h1b, 8'h23, 8'h2b, 8'h34,
        8'h15, 8'h1d, 8'h24, 8'h2d, 8'h2c,
        8'h16, 8'h1e, 8'h26, 8'h25, 8'h2e,
        8'h45, 8'h46, 8'h3e, 8'h3d, 8'h36,
        8'h4d, 8'h44, 8'h43, 8'h3c, 8'h35,
        8'h5a, 8'h4b, 8'h42, 8'h3b, 8'h33,
        8'h29, 8'h14, 8'h3a, 8'h31, 8'h32
    };
    integer key;
    initial begin
        repeat (4) @(negedge clk_sys);
        rst_n = 1;
        repeat (260) @(negedge clk_sys);
        expect_keys(0);
        for (key = 0; key < 40; key = key + 1) begin
            send(MATRIX_CODES[(39-key)*8 +: 8]);
            expect_keys(40'd1 << key);
            release_key(MATRIX_CODES[(39-key)*8 +: 8]);
            expect_keys(0);
        end

        // Physical modifier, cursor and ordinary number sources overlap.
        send(8'h12); send(8'h59); send(8'h2e);
        send(8'he0); send(8'h6b); send(8'h6b);
        expect_keys(40'h0000080001);
        release_key(8'h12); release_key(8'h59); release_key(8'h2e);
        send(8'he0); release_key(8'h6b);
        expect_keys(40'h0000080001);
        release_key(8'h6b);
        expect_keys(0);

        // Punctuation captures its chord on the first make. Both Ctrl
        // keys, the physical Z key and a shifted punctuation key coexist.
        send(8'h14); send(8'he0); send(8'h14); send(8'h1a);
        send(8'h59); send(8'h4c);
        release_key(8'h59); send(8'h4c);
        release_key(8'h14); release_key(8'h1a);
        expect_keys(40'h1000000002);
        release_key(8'h4c);
        expect_keys(40'h1000000000);
        send(8'he0); release_key(8'h14);
        send(8'h66); send(8'h58); send(8'h76);
        expect_keys(40'h0800110001);
        release_key(8'h66); release_key(8'h58); release_key(8'h76);
        expect_keys(0);

        // Bad parity after E0, bad stop after F0, bad start, and a truncated
        // extended break must neither update a key nor poison the next make.
        send(8'he0); frame(8'h6b, 0, 1, 1);
        expect_keys(0);
        send(8'h1c); send(8'h1c); expect_keys(40'h20);
        release_key(8'h1c); expect_keys(0);
        send(8'hf0); frame(8'h1c, 0, 0, 0);
        send(8'h1c); expect_keys(40'h20);
        release_key(8'h1c);
        frame(8'h1c, 1, 0, 1); expect_keys(0);
        send(8'h1c); expect_keys(40'h20);
        release_key(8'h1c);
        send(8'he0); send(8'hf0);
        ps2_bit(0); ps2_bit(1); ps2_bit(0); ps2_data = 1;
        repeat (265) @(negedge clk_sys);
        expect_keys(0);
        send(8'h1c); expect_keys(40'h20);
        release_key(8'h1c);
        send(8'hf0);
        repeat (5010) @(negedge clk_sys);
        send(8'h1c); expect_keys(40'h20);
        release_key(8'h1c);

        send(8'he1); send(8'h14); send(8'h77); send(8'he1);
        send(8'hf0); send(8'h14); send(8'hf0); send(8'h77);
        send(8'he0); send(8'h12); send(8'he0); send(8'h7c);
        expect_keys(0);
        send(8'he1); send(8'h1c); expect_keys(40'h20);
        release_key(8'h1c);
        send(8'h01); send(8'h01); release_key(8'h01); send(8'h01);
        send(8'h09); send(8'h09); send(8'h78); send(8'h07);
        expect_keys(0);
        if (toggles != 2 || rewinds != 1 || {soft_reset_key,recovery_key} !== 2'b11) begin
            $display("FAIL host shortcut press and typematic behavior");
            $finish;
        end
        release_key(8'h78);
        if ({soft_reset_key,recovery_key} !== 2'b01) begin
            $display("FAIL host reset-key release");
            $finish;
        end

        // Reset mid-frame with keys held. The remainder of the old frame
        // passes during the reset re-arm guard.
        send(8'h12); send(8'h29);
        ps2_bit(0); ps2_bit(0);
        rst_n = 0;
        repeat (4) @(negedge clk_sys);
        expect_keys(0);
        if (recovery_key !== 0) begin
            $display("FAIL reset left a host key held");
            $finish;
        end
        rst_n = 1;
        repeat (5) ps2_bit(1);
        ps2_data = 1;
        repeat (260) @(negedge clk_sys);
        expect_keys(0);
        release_key(8'h12); release_key(8'h29); expect_keys(0);
        send(8'h29); expect_keys(40'h0800000000);
        send(8'haa); expect_keys(0);

        // Normalize each switch, exercise both sticks together, then switch
        // the guest mode and B bindings while the physical inputs remain live.
        joy1_n = 6'b111110; joy2_n = 6'b110111; // P1 up / P2 right
        expect_joysticks(1, 8, 5'h1d, 5'h1d, 5'h1f, 8'hff);
        joy1_n = 6'b111101; joy2_n = 6'b111011; // P1 down / P2 left
        expect_joysticks(2, 4, 5'h1e, 5'h1b, 5'h1f, 8'hff);
        joy1_n = 6'b111011; joy2_n = 6'b111110; // P1 left / P2 up
        expect_joysticks(4, 1, 5'h17, 5'h0f, 5'h1f, 8'hff);
        joy1_n = 6'b110111; joy2_n = 6'b111101; // P1 right / P2 down
        expect_joysticks(8, 2, 5'h1b, 5'h17, 5'h1f, 8'hff);
        joy1_n = 6'b101111; joy2_n = 6'h3f; // P1 A only
        expect_joysticks(16, 0, 5'h1f, 5'h1e, 5'h1f, 8'hff);
        joy1_n = 6'b011111; // P1 B only
        expect_joysticks(32, 0, 5'h1f, 5'h1f, 5'h1e, 8'hff);
        joy1_n = 6'h3f; joy2_n = 6'b101111; // P2 A only
        expect_joysticks(0, 16, 5'h0f, 5'h1f, 5'h1f, 8'hff);
        joy2_n = 6'b011111; // P2 B only
        expect_joysticks(0, 32, 5'h1f, 5'h1f, 5'h1e, 8'hff);
        joy1_n = 0; joy2_n = 0;
        expect_joysticks(63, 63, 0, 0, 5'h1e, 8'hff);
        if (fe_keys(8'he7) !== 0 || fe_keys(8'hff) !== 5'h1f) begin
            $display("FAIL fixture FE row selection");
            $finish;
        end
        input_map = 1; b2_map = 2;
        expect_joysticks(63, 63, 0, 5'h1f, 5'h1c, 8'h1f);
        b1_map = 3;
        expect_joysticks(63, 63, 0, 5'h1f, 5'h1d, 8'h3f);
        joy1_n = 6'b111110;
        expect_joysticks(1, 63, 0, 5'h1f, 5'h1d, 8'h08);
        joy1_n = 6'b111101;
        expect_joysticks(2, 63, 0, 5'h1f, 5'h1d, 8'h04);
        joy1_n = 6'b111011;
        expect_joysticks(4, 63, 0, 5'h1f, 5'h1d, 8'h02);
        joy1_n = 6'b110111;
        expect_joysticks(8, 63, 0, 5'h1f, 5'h1d, 8'h01);
        joy1_n = 6'b101111;
        expect_joysticks(16, 63, 0, 5'h1f, 5'h1d, 8'h10);
        joy1_n = 6'b011111;
        expect_joysticks(32, 63, 0, 5'h1f, 5'h1d, 8'h20);
        input_map = 2;
        expect_joysticks(32, 63, 5'h1f, 5'h1f, 5'h1f, 8'hff);

        // A and B share an FE bit with the keyboard. Release in both orders.
        input_map = 0; b1_map = 1; b2_map = 1;
        joy1_n = 6'b001111; joy2_n = 6'h3f;
        send(8'h45); send(8'h29);
        release_key(8'h29); release_key(8'h45);
        expect_joysticks(48, 0, 5'h1f, 5'h1e, 5'h1e, 8'hff);
        send(8'h45); send(8'h29);
        joy1_n = 6'h3f;
        expect_joysticks(0, 0, 5'h1f, 5'h1e, 5'h1e, 8'hff);
        release_key(8'h29); release_key(8'h45);
        expect_joysticks(0, 0, 5'h1f, 5'h1f, 5'h1f, 8'hff);

        $display("PASS PS/2 frames, matrix and shortcuts, dual sticks and FE/Kempston fixture");
        $finish;
    end
endmodule
