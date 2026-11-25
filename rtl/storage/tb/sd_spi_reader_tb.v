`timescale 1ns/1ps
module sd_spi_reader_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset_n = 0, req = 0, we = 0, rx_ready = 0, quiesce = 0;
    reg [31:0] lba = 0;
    wire ready, rx_valid, done, idle, cs, sclk, mosi, tx_ready;
    wire [7:0] rx_data;
    wire [3:0] error;
    reg miso = 1;
    sd_spi_reader #(.INIT_HALF_CYCLES(16'd3), .DATA_HALF_CYCLES(16'd2),
        .INIT_RETRIES(13'd3), .TOKEN_WAIT_BYTES(24'd9),
        .CLIENT_WAIT_CYCLES(24'd25)) dut (
        .clk_sys(clk), .rst_n(reset_n), .sd_blk_req(req),
        .sd_blk_ready(ready), .sd_blk_lba(lba), .sd_blk_we(we),
        .sd_blk_tx_valid(1'b0), .sd_blk_tx_data(8'd0), .sd_blk_tx_ready(tx_ready),
        .sd_blk_rx_valid(rx_valid), .sd_blk_rx_data(rx_data),
        .sd_blk_rx_ready(rx_ready), .sd_blk_done(done), .sd_blk_error(error),
        .media_quiesce(quiesce), .sd_idle(idle), .sd_cs_n(cs),
        .sd_sck(sclk), .sd_mosi(mosi), .sd_miso(miso)
    );

    reg legacy = 0, missing = 0, bad_crc = 0, no_token = 0;
    integer bits, bytes, pointer, high_clocks = 0, starts = 0, polls = 0;
    reg [7:0] buffer [0:521];
    reg [7:0] command_frame [0:5];
    reg [7:0] byte_in;
    reg [31:0] arg;
    integer j;

    // Payload byte i is i modulo 256. CRC computed offline with crc_hqx.
    function [7:0] payload;
        input integer i;
        begin payload = i[7:0]; end
    endfunction

    always @(negedge cs) begin
        bits = 0;
        bytes = 0;
        pointer = 0;
        byte_in = 0;
        for (j = 0; j < 522; j = j + 1) buffer[j] = 8'hff;
        miso = 1;
    end
    always @(posedge sclk) begin
        if (!reset_n) high_clocks = 0;
        else if (cs) begin
            if (mosi !== 1'b1) $fatal(1, "MOSI low during deselected clocks");
            high_clocks = high_clocks + 1;
        end else begin
            byte_in = {byte_in[6:0], mosi};
            bits = bits + 1;
            if (bits == 8) begin
                if (bytes < 6) command_frame[bytes] = byte_in;
                bytes = bytes + 1;
                bits = 0;
                if (bytes == 6 && !missing) begin
                    arg = {command_frame[1], command_frame[2],
                           command_frame[3], command_frame[4]};
                    case (command_frame[0])
                        8'h40: begin
                            if (arg != 0 || command_frame[5] != 8'h95 || high_clocks < 74)
                                $fatal(1, "Invalid CMD0 or startup clocks");
                            starts = starts + 1;
                            polls = 0;
                            buffer[1] = 1;
                        end
                        8'h48: begin
                            if (arg != 32'h1aa || command_frame[5] != 8'h87)
                                $fatal(1, "Invalid CMD8");
                            buffer[1] = legacy ? 5 : 1;
                            buffer[2] = 0;
                            buffer[3] = 0;
                            buffer[4] = 1;
                            buffer[5] = 8'haa;
                        end
                        8'h77: buffer[1] = 1;
                        8'h69: begin
                            if (arg != (legacy ? 32'd0 : 32'h40000000))
                                $fatal(1, "Invalid ACMD41 argument");
                            buffer[1] = polls == 0 ? 1 : 0;
                            polls = polls + 1;
                        end
                        8'h7a: begin
                            buffer[1] = 0;
                            buffer[2] = legacy ? 8'h80 : 8'hc0;
                            buffer[3] = 8'hff;
                            buffer[4] = 8'h80;
                            buffer[5] = 0;
                        end
                        8'h50: begin
                            if (!legacy || arg != 512) $fatal(1, "Invalid CMD16");
                            buffer[1] = 0;
                        end
                        8'h51: begin
                            if (arg != (legacy ? (lba << 9) : lba))
                                $fatal(1, "Wrong CMD17 address %x", arg);
                            buffer[1] = 0;
                            if (!no_token) begin
                                buffer[3] = 8'hfe;
                                for (j = 0; j < 512; j = j + 1)
                                    buffer[4+j] = payload(j);
                                buffer[516] = 8'h40;
                                buffer[517] = bad_crc ? 8'h00 : 8'hda;
                            end
                        end
                        default: $fatal(1, "Unexpected command: %x", command_frame[0]);
                    endcase
                end
            end
        end
    end
    always @(negedge sclk) begin
        if (!cs && bytes >= 6) begin
            pointer = bytes - 6;
            miso = pointer < 522 ? buffer[pointer][7-bits] : 1'b1;
        end else miso = 1;
    end

    task read_block;
        input [31:0] address;
        input write_request;
        input [3:0] expected_error;
        input integer expected_bytes;
        input integer stall_first;
        integer received, stall_cycles;
        reg stalled;
        reg [7:0] stalled_byte;
        begin
            @(negedge clk);
            lba = address;
            we = write_request;
            req = 1;
            rx_ready = 0;
            @(posedge clk);
            if (!ready || !idle) $fatal(1, "Transaction not accepted");
            @(negedge clk);
            req = 0;
            quiesce = 1;
            received = 0;
            stall_cycles = stall_first;
            stalled = 0;
            while (!done) begin
                if (rx_valid && stall_cycles != 0) begin
                    if (stalled && rx_data !== stalled_byte)
                        $fatal(1, "Data changed under backpressure");
                    stalled = 1;
                    stalled_byte = rx_data;
                    stall_cycles = stall_cycles - 1;
                end
                rx_ready = stall_cycles == 0;
                @(posedge clk);
                if (ready || tx_ready) $fatal(1, "Unexpected ready");
                if (rx_valid && rx_ready) begin
                    if (rx_data !== payload(received)) $fatal(1, "Bad byte at %0d", received);
                    received = received + 1;
                end
                @(negedge clk);
            end
            if (error !== expected_error || received != expected_bytes || !cs || sclk)
                $fatal(1, "Completion error=%0d bytes=%0d", error, received);
            quiesce = 0;
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;
        read_block(32'h00123456, 0, 0, 512, 5);
        read_block(32'd123, 0, 0, 512, 0);
        if (starts != 1) $fatal(1, "Second read must reuse initialization");
        read_block(32'd0, 1, 3, 0, 0);
        bad_crc = 1;
        read_block(32'd7, 0, 5, 512, 0);
        bad_crc = 0;
        legacy = 1;
        read_block(32'd8, 0, 0, 512, 0);
        if (starts != 2) $fatal(1, "CRC failure must invalidate initialization");
        read_block(32'h00800000, 0, 2, 0, 0);
        no_token = 1;
        read_block(32'd9, 0, 4, 0, 0);
        no_token = 0;
        missing = 1;
        read_block(32'd0, 0, 1, 0, 0);
        missing = 0;
        read_block(32'd10, 0, 4, 0, 100);
        read_block(32'd10, 0, 0, 512, 0);
        $display("PASS SDHC, SDSC, backpressure, CRC, timeouts, remount and write rejection");
        $finish;
    end
    initial #3000000 $fatal(1, "Watchdog expired");
endmodule
