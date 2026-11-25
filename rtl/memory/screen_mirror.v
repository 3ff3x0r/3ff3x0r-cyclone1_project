module screen_mirror (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire        write_commit,
    input  wire [21:0] write_addr,
    input  wire [7:0]  write_data,
    input  wire        screen_rd_req,
    input  wire        screen_rd_bank7,
    input  wire [12:0] screen_rd_offset,
    output reg         screen_rd_valid,
    output wire [7:0]  screen_rd_data
);
    localparam [12:0] SCREEN_BYTES = 13'd6912;

    wire write_bank7 = (write_addr[21:14] == 8'd7);
    wire write_bank5 = (write_addr[21:14] == 8'd5);
    wire mirror_write = write_commit && (write_bank5 || write_bank7)
        && (write_addr[13:0] < {1'b0, SCREEN_BYTES});
    wire mirror_read = screen_rd_req && (screen_rd_offset < SCREEN_BYTES);

    // Pack bank 7 immediately after bank 5. The offset is 27 * 256,
    // so block 13 holds 256 bytes from each bank at the join. The
    // remaining blocks use all 512 bytes for one bank or the other.
    wire [5:0] write_page = {1'b0, write_addr[12:8]} + (write_bank7 ? 6'd27 : 6'd0);
    wire [5:0] read_page = {1'b0, screen_rd_offset[12:8]} + (screen_rd_bank7 ? 6'd27 : 6'd0);
    wire [8:0] write_index = {write_page[0], write_addr[7:0]};
    wire [8:0] read_index = {read_page[0], screen_rd_offset[7:0]};

    wire forward_write = mirror_read && mirror_write
        && (screen_rd_bank7 == write_bank7)
        && ({1'b0, screen_rd_offset} == write_addr[13:0]);
    reg       forwarded;
    reg [7:0] forwarded_data;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            screen_rd_valid <= 1'b0;
            forwarded <= 1'b0;
            forwarded_data <= 8'b0;
        end else begin
            screen_rd_valid <= mirror_read;
            forwarded <= forward_write;
            if (forward_write)
                forwarded_data <= write_data;
        end
    end

    reg [4:0] read_block;
    always @(posedge clk_sys)
        if (mirror_read)
            read_block <= read_page[5:1];

    wire [27*8-1:0] block_data;
    genvar block_number;
    generate
        for (block_number = 0; block_number < 27; block_number = block_number + 1) begin : blocks
            localparam [4:0] BLOCK_NUMBER = block_number;
            wire enable_write = mirror_write && (write_page[5:1] == BLOCK_NUMBER);
            // One Cyclone I M4K per array. The external byte bypass defines
            // the mixed-port collision result. Guest initialization writes
            // both mirrors through the normal commit path.
            (* ramstyle = "M4K, no_rw_check" *) reg [7:0] bytes [0:511];
            reg [7:0] read_byte;

            always @(posedge clk_sys) begin
                if (enable_write)
                    bytes[write_index] <= write_data;
                read_byte <= bytes[read_index];
            end

            assign block_data[block_number*8 +: 8] = read_byte;
        end
    endgenerate

    assign screen_rd_data = forwarded ? forwarded_data : block_data[read_block*8 +: 8];
endmodule
