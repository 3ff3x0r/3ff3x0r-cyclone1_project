module sd_spi_reader #(
    // Default for 85.909 MHz fabric. Mode 0, 397.7 kHz / 10.74 MHz.
    parameter [15:0] INIT_HALF_CYCLES = 108,
    parameter [15:0] DATA_HALF_CYCLES = 4,
    parameter [12:0] INIT_RETRIES = 4096,
    parameter [23:0] TOKEN_WAIT_BYTES = 262144,
    parameter [23:0] CLIENT_WAIT_CYCLES = 8580000
) (
    input wire clk_sys, rst_n,
    input wire sd_blk_req,
    output wire sd_blk_ready,
    input wire [31:0] sd_blk_lba,
    input wire sd_blk_we,
    input wire sd_blk_tx_valid,
    input wire [7:0] sd_blk_tx_data,
    output wire sd_blk_tx_ready,
    output reg sd_blk_rx_valid,
    output reg [7:0] sd_blk_rx_data,
    input wire sd_blk_rx_ready,
    output reg sd_blk_done,
    output reg [3:0] sd_blk_error,
    input wire media_quiesce,
    output wire sd_idle,
    output reg sd_cs_n,
    output reg sd_sck,
    output wire sd_mosi,
    input wire sd_miso
);
    localparam [3:0] IDLE=0, POWER=1, COMMAND=2, RESPONSE=3, EXTENSION=4,
        EVALUATE=5, GAP=6, NEXT_COMMAND=7, TOKEN=8, DATA=9, OFFER=10,
        CRC_HI=11, CRC_LO=12, COMPLETE=13, READ_ADDRESS=14;
    localparam CMD0=6'd0, CMD8=6'd8, CMD16=6'd16, CMD17=6'd17,
        CMD41=6'd41, CMD55=6'd55, CMD58=6'd58;
    reg [3:0] state, after_gap;
    reg [5:0] command, next_command;
    reg [31:0] argument, next_argument, lba, extension;
    reg [7:0] response, crc_hi;
    reg [5:0] count;
    reg [8:0] offset;
    reg [12:0] retries;
    reg [23:0] wait_count;
    reg [15:0] sector_crc;
    reg initialized, version2, block_addressing;

    reg shifting, byte_done;
    reg [15:0] divider;
    reg [2:0] bit_index;
    reg [7:0] outgoing, incoming;
    reg [7:0] next_byte;
    wire [15:0] half_period = initialized ? DATA_HALF_CYCLES : INIT_HALF_CYCLES;
    wire transfer = state == POWER || state == COMMAND || state == RESPONSE ||
                    state == EXTENSION || state == GAP || state == TOKEN ||
                    state == DATA || state == CRC_HI || state == CRC_LO;

    assign sd_mosi = shifting ? outgoing[7] : 1'b1;
    assign sd_blk_ready = (state == IDLE) && !media_quiesce && rst_n;
    assign sd_idle = state == IDLE && !sd_blk_done;
    assign sd_blk_tx_ready = 1'b0;
    wire unused_extension_bits = &{1'b0, extension[29:24]};
    wire unused_write_stream = &{1'b0, sd_blk_tx_valid, sd_blk_tx_data};

    always @* begin
        next_byte = 8'hff;
        if (state == COMMAND) begin
            case (count)
                0: next_byte = {2'b01, command};
                1: next_byte = argument[31:24];
                2: next_byte = argument[23:16];
                3: next_byte = argument[15:8];
                4: next_byte = argument[7:0];
                5: begin
                    if (command == CMD0) next_byte = 8'h95;
                    if (command == CMD8) next_byte = 8'h87;
                end
                default: next_byte = 8'hff;
            endcase
        end
    end

    // Keep MOSI stable on the rising edge and advance it on the falling edge.
    always @(posedge clk_sys) begin
        if (!rst_n) begin
            sd_sck <= 0;
            shifting <= 0;
            byte_done <= 0;
            divider <= 0;
            bit_index <= 0;
            outgoing <= 8'hff;
            incoming <= 0;
        end else begin
            byte_done <= 0;
            if (!shifting) begin
                if (transfer && !byte_done) begin
                    shifting <= 1;
                    outgoing <= next_byte;
                    bit_index <= 0;
                    divider <= half_period - 16'd1;
                end
            end else if (divider != 0) begin
                divider <= divider - 1'b1;
            end else begin
                divider <= half_period - 16'd1;
                sd_sck <= !sd_sck;
                if (!sd_sck) begin
                    incoming <= {incoming[6:0], sd_miso};
                end else if (bit_index == 7) begin
                    shifting <= 0;
                    byte_done <= 1;
                end else begin
                    outgoing <= {outgoing[6:0], 1'b1};
                    bit_index <= bit_index + 1'b1;
                end
            end
        end
    end

    function [15:0] crc16_byte;
        input [15:0] previous;
        input [7:0] data;
        integer bit_number;
        reg [15:0] crc;
        begin
            crc = previous ^ {data, 8'b0};
            for (bit_number=0; bit_number<8; bit_number=bit_number+1)
                crc = {crc[14:0], 1'b0} ^ (crc[15] ? 16'h1021 : 16'h0000);
            crc16_byte = crc;
        end
    endfunction

    // Raise CS and supply eight clocks before reselecting or completing.
    task deselect;
        input [3:0] destination;
        begin
            sd_cs_n <= 1;
            state <= GAP;
            after_gap <= destination;
        end
    endtask

    task finish;
        input [3:0] error;
        begin
            sd_blk_error <= error;
            if (error == 1 || error == 4 || error == 5)
                initialized <= 0;
            deselect(COMPLETE);
        end
    endtask

    task queue_command;
        input [5:0] index;
        input [31:0] value;
        begin
            next_command <= index;
            next_argument <= value;
            deselect(NEXT_COMMAND);
        end
    endtask

    always @(posedge clk_sys) begin
        if (!rst_n) begin
            state <= IDLE;
            after_gap <= IDLE;
            command <= 0;
            next_command <= 0;
            argument <= 0;
            next_argument <= 0;
            lba <= 0;
            response <= 0;
            extension <= 0;
            count <= 0;
            offset <= 0;
            retries <= 0;
            wait_count <= 0;
            sector_crc <= 0;
            crc_hi <= 0;
            initialized <= 0;
            version2 <= 0;
            block_addressing <= 0;
            sd_cs_n <= 1;
            sd_blk_rx_valid <= 0;
            sd_blk_rx_data <= 0;
            sd_blk_done <= 0;
            sd_blk_error <= 0;
        end else begin
            sd_blk_done <= 0;
            case (state)
                IDLE: if (sd_blk_req && sd_blk_ready) begin
                    lba <= sd_blk_lba;
                    if (sd_blk_we) begin
                        sd_blk_error <= 3;
                        state <= COMPLETE;
                    end else if (initialized) begin
                        state <= READ_ADDRESS;
                    end else begin
                        count <= 0;
                        retries <= 0;
                        version2 <= 0;
                        block_addressing <= 0;
                        state <= POWER;
                    end
                end
                POWER: if (byte_done) begin
                    // At the default divider, 512 clocks give 1.29 ms with CS high.
                    if (count == 63) begin
                        next_command <= CMD0;
                        next_argument <= 0;
                        state <= NEXT_COMMAND;
                    end else count <= count + 1'b1;
                end
                NEXT_COMMAND: begin
                    sd_cs_n <= 0;
                    command <= next_command;
                    argument <= next_argument;
                    count <= 0;
                    state <= COMMAND;
                end
                COMMAND: if (byte_done) begin
                    if (count == 5) begin
                        count <= 0;
                        state <= RESPONSE;
                    end else count <= count + 1'b1;
                end
                RESPONSE: if (byte_done) begin
                    if (!incoming[7]) begin
                        response <= incoming;
                        count <= 0;
                        if ((command == CMD8 && incoming == 1) ||
                            (command == CMD58 && incoming == 0))
                            state <= EXTENSION;
                        else state <= EVALUATE;
                    end else if (count == 7) begin
                        finish(command == CMD0 ? 4'd1 : 4'd4);
                    end else count <= count + 1'b1;
                end
                EXTENSION: if (byte_done) begin
                    extension <= {extension[23:0], incoming};
                    if (count == 3) state <= EVALUATE;
                    else count <= count + 1'b1;
                end
                EVALUATE: case (command)
                    CMD0: if (response == 1) queue_command(CMD8, 32'h1aa);
                          else finish(5);
                    CMD8: if (response == 1 && extension[11:0] == 12'h1aa) begin
                              version2 <= 1;
                              queue_command(CMD55, 0);
                          end else if (response == 5) queue_command(CMD55, 0);
                          else finish(5);
                    CMD55: if (response == 0 || response == 1)
                               queue_command(CMD41, version2 ? 32'h40000000 : 32'd0);
                           else finish(5);
                    CMD41: if (response == 0) queue_command(CMD58, 0);
                           else if (response != 1) finish(5);
                           else if (retries == INIT_RETRIES-13'd1) finish(4);
                           else begin
                               retries <= retries + 1'b1;
                               queue_command(CMD55, 0);
                           end
                    CMD58: if (response != 0 || !extension[31] ||
                               !extension[20]) finish(5);
                           else if (version2 && extension[30]) begin
                               block_addressing <= 1;
                               initialized <= 1;
                               deselect(READ_ADDRESS);
                           end else queue_command(CMD16, 512);
                    CMD16: if (response == 0) begin
                               initialized <= 1;
                               deselect(READ_ADDRESS);
                           end else finish(5);
                    CMD17: if (response == 0) begin
                               wait_count <= 0;
                               offset <= 0;
                               sector_crc <= 0;
                               state <= TOKEN;
                           end else if (response[5] || response[6]) finish(2);
                           else finish(5);
                    default: finish(5);
                endcase
                GAP: if (byte_done) state <= after_gap;
                READ_ADDRESS: if (!block_addressing && lba[31:23] != 0) begin
                    sd_blk_error <= 2;
                    state <= COMPLETE;
                end else begin
                    next_command <= CMD17;
                    next_argument <= block_addressing ? lba : {lba[22:0], 9'b0};
                    state <= NEXT_COMMAND;
                end
                TOKEN: if (byte_done) begin
                    if (incoming == 8'hfe) state <= DATA;
                    else if (incoming != 8'hff) finish(5);
                    else if (wait_count == TOKEN_WAIT_BYTES-24'd1) finish(4);
                    else wait_count <= wait_count + 1'b1;
                end
                DATA: if (byte_done) begin
                    sector_crc <= crc16_byte(sector_crc, incoming);
                    sd_blk_rx_data <= incoming;
                    sd_blk_rx_valid <= 1;
                    wait_count <= 0;
                    state <= OFFER;
                end
                OFFER: if (sd_blk_rx_ready) begin
                    sd_blk_rx_valid <= 0;
                    if (offset == 511) state <= CRC_HI;
                    else begin
                        offset <= offset + 1'b1;
                        state <= DATA;
                    end
                end else if (wait_count == CLIENT_WAIT_CYCLES-24'd1) begin
                    sd_blk_rx_valid <= 0;
                    finish(4);
                end else wait_count <= wait_count + 1'b1;
                CRC_HI: if (byte_done) begin
                    crc_hi <= incoming;
                    state <= CRC_LO;
                end
                CRC_LO: if (byte_done)
                    finish({crc_hi, incoming} == sector_crc ? 4'd0 : 4'd5);
                COMPLETE: begin
                    sd_blk_done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
