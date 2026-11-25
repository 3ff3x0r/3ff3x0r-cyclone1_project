module tap_player (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire        guest_reset_n,
    input  wire        boot_overlay,
    input  wire        media_quiesce,
    input  wire        ce_cpu,
    input  wire [2:0]  cfg_timing_id,

    input  wire        tap_mount_update,
    input  wire        tap_mounted,
    input  wire [21:0] tap_base,
    input  wire [31:0] tap_length,

    output wire        tap_rd_req,
    output wire [31:0] tap_rd_offset,
    input  wire        tap_rd_accept,
    input  wire        tap_rd_valid,
    input  wire [7:0]  tap_rd_data,

    input  wire        tap_play_toggle,
    input  wire        tap_rewind,
    output wire        tap_playing,
    output wire        tap_ear_valid,
    output reg         tap_ear_bit,
    output wire        tap_idle
);
    localparam [21:0] CACHE_BASE = 22'h080000;
    localparam [21:0] CACHE_END  = 22'h100000;

    localparam [21:0] PILOT_TICKS = 22'd2168,
                      SYNC1_TICKS = 22'd667,
                      SYNC2_TICKS = 22'd735;

    localparam [2:0] LENGTH_LO = 3'd0, LENGTH_HI = 3'd1, FLAG_BYTE = 3'd2,
                     BLOCK_READY = 3'd3, NO_BLOCK = 3'd4;
    localparam [2:0] START = 3'd0, PILOT = 3'd1, SYNC1 = 3'd2, SYNC2 = 3'd3,
                     DATA = 3'd4, GAP = 3'd5, FINISHED = 3'd6;

    // Validate the physical span before narrowing. Ticket E translates the
    // file-relative requests. The narrowed length covers the full cache.
    wire [22:0] mount_end = {1'b0, tap_base} + {3'd0, tap_length[19:0]};
    wire mount_ok = tap_mounted && (tap_base >= CACHE_BASE) &&
                    (tap_length[31:20] == 12'd0) && (tap_length[19:0] != 20'd0) &&
                    (mount_end <= {1'b0, CACHE_END});
    reg mounted;
    reg [19:0] file_length;

    reg [19:0] read_offset;
    reg read_offered, read_pending, discard_response;
    reg byte_valid;
    reg [7:0] prefetched_byte;

    reg play_requested;
    reg [2:0] header_state, phase;
    reg [7:0] length_lo, shift_byte;
    reg [15:0] block_bytes_left;
    reg [12:0] pilot_left;
    reg [2:0] bit_index;
    reg second_half;
    reg [21:0] ticks_left;
    reg [21:0] gap_ticks;

    wire transport_enabled = rst_n && guest_reset_n && mounted &&
                             !boot_overlay && !media_quiesce && !tap_mount_update;
    wire restart = !guest_reset_n || tap_mount_update ||
                   (transport_enabled && tap_rewind);
    wire run = tap_playing && !tap_play_toggle && !restart;
    wire tick = run && ce_cpu;
    wire pulse_end = tick && (ticks_left == 22'd1);

    wire header_pending = (header_state == LENGTH_LO) ||
                          (header_state == LENGTH_HI) || (header_state == FLAG_BYTE);
    wire take_header = run && header_pending && byte_valid;
    wire last_bit = second_half && (bit_index == 3'd0);
    wire take_data = pulse_end && (phase == DATA) && last_bit &&
                     (block_bytes_left > 16'd1) && byte_valid;
    wire [15:0] block_length = {prefetched_byte, length_lo};
    // With the high length byte buffered, read_offset points just beyond it.
    wire [20:0] block_end = {1'b0, read_offset} + {5'd0, block_length};

    assign tap_rd_req = read_offered && transport_enabled && !restart;
    assign tap_rd_offset = {12'd0, read_offset};
    assign tap_idle = !tap_rd_req && !read_pending;
    assign tap_playing = transport_enabled && play_requested && (phase != FINISHED);
    assign tap_ear_valid = tap_playing && (phase != START);

    function [21:0] bit_ticks;
        input data_bit;
        begin
            bit_ticks = data_bit ? 22'd1710 : 22'd855;
        end
    endfunction

    // One second at the model's nominal base ce_cpu rate.
    always @* begin
        case (cfg_timing_id)
            3'd1, 3'd2: gap_ticks = 22'd3546900;
            3'd3, 3'd4: gap_ticks = 22'd3575610;
            default:    gap_ticks = 22'd3500000;
        endcase
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            mounted     <= 1'b0;
            file_length <= 20'd0;
        end else if (tap_mount_update) begin
            mounted     <= mount_ok;
            file_length <= mount_ok ? tap_length[19:0] : 20'd0;
        end
    end

    // One byte of lookahead is enough for staged SDRAM. Each data byte
    // provides at least 13,680 T-states to prefetch the next byte. A read
    // already offered stays up through a play/pause toggle until accepted.
    // Quiesce and transport restarts gate unaccepted offers immediately.
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            read_offset      <= 20'd0;
            read_offered     <= 1'b0;
            read_pending     <= 1'b0;
            discard_response <= 1'b0;
            byte_valid       <= 1'b0;
            prefetched_byte  <= 8'd0;
        end else begin
            if (!transport_enabled || restart) begin
                read_offered <= 1'b0;
            end else if (tap_rd_req && tap_rd_accept) begin
                read_offered <= 1'b0;
                read_offset  <= read_offset + 20'd1;
                read_pending <= 1'b1;
            end else if (run && !read_pending && !byte_valid &&
                         (header_state != NO_BLOCK) && (read_offset < file_length)) begin
                read_offered <= 1'b1;
            end

            if (read_pending && tap_rd_valid) begin
                read_pending     <= 1'b0;
                discard_response <= 1'b0;
                if (!discard_response && !restart) begin
                    prefetched_byte <= tap_rd_data;
                    byte_valid      <= 1'b1;
                end
            end

            if (take_header || take_data)
                byte_valid <= 1'b0;

            // Guest reset and rewind can invalidate the byte, but only
            // receiving its response frees an accepted transaction slot.
            if (restart) begin
                read_offset      <= 20'd0;
                byte_valid       <= 1'b0;
                discard_response <= read_pending && !tap_rd_valid;
            end
        end
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            play_requested   <= 1'b0;
            header_state     <= LENGTH_LO;
            phase            <= START;
            length_lo        <= 8'd0;
            shift_byte       <= 8'd0;
            block_bytes_left <= 16'd0;
            pilot_left       <= 13'd0;
            bit_index        <= 3'd0;
            second_half      <= 1'b0;
            ticks_left       <= 22'd0;
            tap_ear_bit      <= 1'b0;
        end else if (restart) begin
            play_requested <= 1'b0;
            header_state   <= LENGTH_LO;
            phase          <= START;
            ticks_left     <= 22'd0;
            tap_ear_bit    <= 1'b0;
        end else if (transport_enabled && tap_play_toggle && (phase != FINISHED)) begin
            play_requested <= !play_requested;
        end else if (run) begin
            // Decode a new block during startup or while the gap counts
            // down. The flag controls the pilot and is also sent as data.
            if (take_header) begin
                case (header_state)
                    LENGTH_LO: begin
                        length_lo    <= prefetched_byte;
                        header_state <= LENGTH_HI;
                    end
                    LENGTH_HI: begin
                        block_bytes_left <= block_length;
                        if ((block_length == 16'd0) || (block_end > {1'b0, file_length}))
                            header_state <= NO_BLOCK;
                        else
                            header_state <= FLAG_BYTE;
                    end
                    FLAG_BYTE: begin
                        shift_byte   <= prefetched_byte;
                        header_state <= BLOCK_READY;
                    end
                    default: header_state <= NO_BLOCK;
                endcase
            end else if (header_pending && !byte_valid && !read_pending &&
                         (read_offset == file_length)) begin
                header_state <= NO_BLOCK;
            end

            if (tick && (ticks_left != 22'd0))
                ticks_left <= ticks_left - 22'd1;

            if ((phase == START && tick && header_state == BLOCK_READY) ||
                (phase == GAP && pulse_end && header_state == BLOCK_READY)) begin
                pilot_left  <= shift_byte[7] ? 13'd3223 : 13'd8063;
                ticks_left  <= PILOT_TICKS;
                tap_ear_bit <= 1'b1;
                phase       <= PILOT;
            end else if (phase == START && header_state == NO_BLOCK) begin
                phase <= FINISHED;
            end else if (pulse_end) begin
                case (phase)
                    PILOT: begin
                        tap_ear_bit <= !tap_ear_bit;
                        pilot_left  <= pilot_left - 13'd1;
                        if (pilot_left == 13'd1) begin
                            ticks_left <= SYNC1_TICKS;
                            phase      <= SYNC1;
                        end else begin
                            ticks_left <= PILOT_TICKS;
                        end
                    end
                    SYNC1: begin
                        tap_ear_bit <= !tap_ear_bit;
                        ticks_left  <= SYNC2_TICKS;
                        phase       <= SYNC2;
                    end
                    SYNC2: begin
                        tap_ear_bit <= !tap_ear_bit;
                        ticks_left  <= bit_ticks(shift_byte[7]);
                        bit_index   <= 3'd7;
                        second_half <= 1'b0;
                        phase       <= DATA;
                    end
                    DATA: begin
                        tap_ear_bit <= !tap_ear_bit;
                        second_half <= !second_half;
                        if (!second_half) begin
                            ticks_left <= bit_ticks(shift_byte[7]);
                        end else if (!last_bit) begin
                            shift_byte <= {shift_byte[6:0], 1'b0};
                            bit_index  <= bit_index - 3'd1;
                            ticks_left <= bit_ticks(shift_byte[6]);
                        end else if (block_bytes_left == 16'd1) begin
                            // Starting high with an odd pilot count puts the
                            // final data edge low for the entire pause.
                            header_state <= LENGTH_LO;
                            ticks_left   <= gap_ticks;
                            phase        <= GAP;
                        end else if (take_data) begin
                            block_bytes_left <= block_bytes_left - 16'd1;
                            shift_byte       <= prefetched_byte;
                            bit_index        <= 3'd7;
                            ticks_left       <= bit_ticks(prefetched_byte[7]);
                        end else begin
                            // A missed SDRAM deadline ends playback instead
                            // of stretching a ROM-loader pulse.
                            phase <= FINISHED;
                        end
                    end
                    GAP: phase <= FINISHED;
                    default: phase <= FINISHED;
                endcase
            end
        end
    end
endmodule
