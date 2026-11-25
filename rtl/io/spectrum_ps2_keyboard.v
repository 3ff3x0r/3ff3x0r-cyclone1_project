module spectrum_ps2_keyboard #(
    parameter integer PREFIX_TIMEOUT_CYCLES = 429546
) (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire [7:0]  byte_data,
    input  wire        byte_valid,
    input  wire        frame_error,
    output wire [39:0] key_matrix_n,
    output wire        soft_reset_key,
    output wire        recovery_key,
    output wire        tap_play_toggle,
    output wire        tap_rewind
);
    function integer count_width;
        input integer maximum;
        integer remaining;
        begin
            count_width = 1;
            for (remaining = maximum >> 1; remaining > 0; remaining = remaining >> 1)
                count_width = count_width + 1;
        end
    endfunction

    localparam integer LAST_TICK = PREFIX_TIMEOUT_CYCLES - 1;
    localparam integer TIMER_WIDTH = count_width(LAST_TICK);
    localparam [TIMER_WIDTH-1:0] TIMEOUT = LAST_TICK[TIMER_WIDTH-1:0];
    reg [TIMER_WIDTH-1:0] prefix_ticks;
    reg extended_pending, break_pending;
    reg [2:0] pause_index;
    reg [7:0] pause_expected;
    always @* begin
        case (pause_index)
            3'd1, 3'd5: pause_expected = 8'h14;
            3'd2, 3'd7: pause_expected = 8'h77;
            3'd3:       pause_expected = 8'he1;
            default:    pause_expected = 8'hf0;
        endcase
    end

    wire keyboard_reset = byte_valid && byte_data == 8'haa; // PS/2 startup self-test passed
    wire pause_byte = pause_index != 0 && byte_data == pause_expected;
    wire key_update = byte_valid && !pause_byte;
    wire [8:0] scan = {extended_pending, byte_data};

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            extended_pending <= 1'b0;
            break_pending <= 1'b0;
            pause_index <= 0;
            prefix_ticks <= 0;
        end else if (frame_error || keyboard_reset) begin
            extended_pending <= 1'b0;
            break_pending <= 1'b0;
            pause_index <= 0;
            prefix_ticks <= 0;
        end else if (byte_valid) begin
            prefix_ticks <= 0;
            extended_pending <= 1'b0;
            break_pending <= 1'b0;
            if (pause_byte) begin
                // Consume the complete E1 sequence without turning its Ctrl
                // bytes into guest keys. The index rolls over after byte seven.
                pause_index <= pause_index + 3'd1;
            end else begin
                pause_index <= 0;
                case (byte_data)
                    8'he1: pause_index <= 3'd1;
                    8'he0: extended_pending <= !extended_pending && !break_pending;
                    8'hf0: begin
                        extended_pending <= extended_pending && !break_pending;
                        break_pending <= !break_pending;
                    end
                    default: begin end
                endcase
            end
        end else if (prefix_ticks == TIMEOUT) begin
            extended_pending <= 1'b0;
            break_pending <= 1'b0;
            pause_index <= 0;
            prefix_ticks <= 0;
        end else if (extended_pending || break_pending || pause_index != 0)
            prefix_ticks <= prefix_ticks + 1'b1;
    end

    // One physical source per Spectrum matrix position, in FE row/bit order.
    function [7:0] direct_scan;
        input integer key;
        begin
            case (key)
                 0: direct_scan = 8'h12; // L Shift, Z, X, C, V
                 1: direct_scan = 8'h1a;
                 2: direct_scan = 8'h22;
                 3: direct_scan = 8'h21;
                 4: direct_scan = 8'h2a;
                 5: direct_scan = 8'h1c; // A, S, D, F, G
                 6: direct_scan = 8'h1b;
                 7: direct_scan = 8'h23;
                 8: direct_scan = 8'h2b;
                 9: direct_scan = 8'h34;
                10: direct_scan = 8'h15; // Q, W, E, R, T
                11: direct_scan = 8'h1d;
                12: direct_scan = 8'h24;
                13: direct_scan = 8'h2d;
                14: direct_scan = 8'h2c;
                15: direct_scan = 8'h16; // 1, 2, 3, 4, 5
                16: direct_scan = 8'h1e;
                17: direct_scan = 8'h26;
                18: direct_scan = 8'h25;
                19: direct_scan = 8'h2e;
                20: direct_scan = 8'h45; // 0, 9, 8, 7, 6
                21: direct_scan = 8'h46;
                22: direct_scan = 8'h3e;
                23: direct_scan = 8'h3d;
                24: direct_scan = 8'h36;
                25: direct_scan = 8'h4d; // P, O, I, U, Y
                26: direct_scan = 8'h44;
                27: direct_scan = 8'h43;
                28: direct_scan = 8'h3c;
                29: direct_scan = 8'h35;
                30: direct_scan = 8'h5a; // Enter, L, K, J, H
                31: direct_scan = 8'h4b;
                32: direct_scan = 8'h42;
                33: direct_scan = 8'h3b;
                34: direct_scan = 8'h33;
                35: direct_scan = 8'h29; // Space, L Ctrl, M, N, B
                36: direct_scan = 8'h14;
                37: direct_scan = 8'h3a;
                38: direct_scan = 8'h31;
                39: direct_scan = 8'h32;
                default: direct_scan = 8'h00;
            endcase
        end
    endfunction

    localparam RS = 0, RC = 1, KP_ENTER = 2, LEFT = 3, DOWN = 4, UP = 5, RIGHT = 6,
               KP_LEFT = 7, KP_DOWN = 8, KP_UP = 9, KP_RIGHT = 10,
               BACKSPACE = 11, CAPS_LOCK = 12, ESC = 13, LBRACKET = 14, RBRACKET = 15,
               GRAVE = 16, BACKSLASH = 17, KP_SLASH = 18, F9 = 19, F10 = 20,
               F11 = 21, F12 = 22;

    function [8:0] extra_scan;
        input integer key;
        begin
            case (key)
                RS:        extra_scan = 9'h059;
                RC:        extra_scan = 9'h114;
                KP_ENTER:  extra_scan = 9'h15a;
                LEFT:      extra_scan = 9'h16b;
                DOWN:      extra_scan = 9'h172;
                UP:        extra_scan = 9'h175;
                RIGHT:     extra_scan = 9'h174;
                KP_LEFT:   extra_scan = 9'h06b;
                KP_DOWN:   extra_scan = 9'h072;
                KP_UP:     extra_scan = 9'h075;
                KP_RIGHT:  extra_scan = 9'h074;
                BACKSPACE: extra_scan = 9'h066;
                CAPS_LOCK: extra_scan = 9'h058;
                ESC:       extra_scan = 9'h076;
                LBRACKET:  extra_scan = 9'h054;
                RBRACKET:  extra_scan = 9'h05b;
                GRAVE:     extra_scan = 9'h00e;
                BACKSLASH: extra_scan = 9'h05d;
                KP_SLASH:  extra_scan = 9'h14a;
                F9:        extra_scan = 9'h001;
                F10:       extra_scan = 9'h009;
                F11:       extra_scan = 9'h078;
                F12:       extra_scan = 9'h007;
                default:   extra_scan = 9'h000;
            endcase
        end
    endfunction

    localparam DOT = 0, COMMA = 1, SLASH = 2, SEMICOLON = 3, QUOTE = 4, MINUS = 5, EQUALS = 6;
    function [7:0] punctuation_scan;
        input integer key;
        begin
            case (key)
                DOT:       punctuation_scan = 8'h49;
                COMMA:     punctuation_scan = 8'h41;
                SLASH:     punctuation_scan = 8'h4a;
                SEMICOLON: punctuation_scan = 8'h4c;
                QUOTE:     punctuation_scan = 8'h52;
                MINUS:     punctuation_scan = 8'h4e;
                EQUALS:    punctuation_scan = 8'h55;
                default:   punctuation_scan = 8'h00;
            endcase
        end
    endfunction

    wire [39:0] direct;
    wire [F12:0] extra;
    wire [EQUALS:0] plain, shifted;
    genvar index;
    generate
        for (index = 0; index < 40; index = index + 1) begin : matrix_sources
            reg held;
            always @(posedge clk_sys or negedge rst_n) begin
                if (!rst_n)
                    held <= 1'b0;
                else if (keyboard_reset)
                    held <= 1'b0;
                else if (key_update && scan == {1'b0, direct_scan(index)})
                    held <= !break_pending;
            end
            assign direct[index] = held;
        end
        for (index = 0; index <= F12; index = index + 1) begin : extra_sources
            reg held;
            always @(posedge clk_sys or negedge rst_n) begin
                if (!rst_n)
                    held <= 1'b0;
                else if (keyboard_reset)
                    held <= 1'b0;
                else if (key_update && scan == extra_scan(index))
                    held <= !break_pending;
            end
            assign extra[index] = held;
        end
        for (index = 0; index <= EQUALS; index = index + 1) begin : punctuation_sources
            reg held, shifted_at_make;
            always @(posedge clk_sys or negedge rst_n) begin
                if (!rst_n) begin
                    held <= 1'b0;
                    shifted_at_make <= 1'b0;
                end else if (keyboard_reset)
                    held <= 1'b0;
                else if (key_update && scan == {1'b0, punctuation_scan(index)}) begin
                    held <= !break_pending;
                    if (!held && !break_pending)
                        shifted_at_make <= extra[RS];
                end
            end
            assign plain[index] = held && !shifted_at_make;
            assign shifted[index] = held && shifted_at_make;
        end
    endgenerate

    wire left = extra[LEFT] || extra[KP_LEFT];
    wire down = extra[DOWN] || extra[KP_DOWN];
    wire up = extra[UP] || extra[KP_UP];
    wire right = extra[RIGHT] || extra[KP_RIGHT];
    reg [39:0] shortcuts;
    always @* begin
        shortcuts = 0;
        shortcuts[0] = extra[RS] || left || down || up || right ||
                       extra[BACKSPACE] || extra[CAPS_LOCK] || extra[ESC];
        shortcuts[1] = shifted[SEMICOLON];
        shortcuts[3] = shifted[SLASH];
        shortcuts[4] = plain[SLASH] || extra[KP_SLASH];
        shortcuts[13] = shifted[COMMA];
        shortcuts[14] = shifted[DOT];
        shortcuts[16] = extra[CAPS_LOCK];
        shortcuts[19] = left;
        shortcuts[20] = extra[BACKSPACE] || plain[MINUS];
        shortcuts[21] = extra[RBRACKET];
        shortcuts[22] = right || extra[LBRACKET];
        shortcuts[23] = up || shifted[QUOTE] || extra[GRAVE];
        shortcuts[24] = down;
        shortcuts[25] = plain[QUOTE];
        shortcuts[26] = plain[SEMICOLON];
        shortcuts[30] = extra[KP_ENTER];
        shortcuts[31] = shifted[EQUALS];
        shortcuts[32] = plain[EQUALS];
        shortcuts[33] = shifted[MINUS];
        shortcuts[35] = extra[ESC];
        shortcuts[36] = extra[RC] || (|plain) || (|shifted) ||
                        extra[LBRACKET] || extra[RBRACKET] || extra[GRAVE] ||
                        extra[BACKSLASH] || extra[KP_SLASH];
        shortcuts[37] = plain[DOT];
        shortcuts[38] = plain[COMMA];
        shortcuts[39] = extra[BACKSLASH];
    end
    assign key_matrix_n = ~(direct | shortcuts);
    assign tap_play_toggle = key_update && !break_pending && scan == extra_scan(F9) && !extra[F9];
    assign tap_rewind = key_update && !break_pending && scan == extra_scan(F10) && !extra[F10];
    assign soft_reset_key = extra[F11];
    assign recovery_key = extra[F12];
endmodule
