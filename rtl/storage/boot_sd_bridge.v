module boot_sd_bridge (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire        sd_owner_boot,
    input  wire        media_quiesce,
    output wire        boot_sd_idle,

    input  wire        boot_bus_req,
    input  wire        boot_bus_io,
    input  wire        boot_bus_we,
    input  wire [15:0] boot_bus_addr,
    input  wire [7:0]  boot_bus_wdata,
    output wire        boot_bus_ready,
    output reg  [7:0]  boot_bus_rdata,

    output wire        sd_blk_req,
    input  wire        sd_blk_ready,
    output wire [31:0] sd_blk_lba,
    output wire        sd_blk_we,
    output wire        sd_blk_tx_valid,
    output wire [7:0]  sd_blk_tx_data,
    input  wire        sd_blk_rx_valid,
    input  wire [7:0]  sd_blk_rx_data,
    output wire        sd_blk_rx_ready,
    input  wire        sd_blk_done,
    input  wire [3:0]  sd_blk_error
);
    localparam [7:0] PORT_LBA0 = 8'hd0, PORT_LBA1 = 8'hd1,
        PORT_LBA2 = 8'hd2, PORT_LBA3 = 8'hd3,
        PORT_CONTROL = 8'hd4, PORT_DATA = 8'hd5;
    localparam [1:0] IDLE = 2'd0, REQUEST = 2'd1, RECEIVE = 2'd2;
    localparam [3:0] ERROR_IO = 4'd5;

    reg [1:0] state;
    reg [31:0] lba;
    reg [9:0] offset;
    reg done, data_valid;
    reg [3:0] error;
    (* ramstyle = "M4K, no_rw_check" *) reg [7:0] sector_buffer [0:511];
    reg [7:0] sector_byte;
    reg data_pending;

    // Z80 immediate I/O and block I/O both vary the upper address byte.
    wire [7:0] port_number = boot_bus_addr[7:0];
    wire unused_high_addr = &{1'b0, boot_bus_addr[15:8]};
    wire selected = rst_n && boot_bus_req && boot_bus_io &&
                    port_number >= PORT_LBA0 && port_number <= PORT_DATA;
    wire busy = state != IDLE;
    wire available = sd_owner_boot && data_valid;
    wire data_read = selected && !boot_bus_we && port_number == PORT_DATA;
    wire data_fetch = data_read && available && !data_pending;
    wire data_take = data_read && available && data_pending;
    wire register_write = boot_bus_ready && boot_bus_we && !busy &&
                          sd_owner_boot && !media_quiesce;
    wire start = register_write && port_number == PORT_CONTROL && boot_bus_wdata[0];

    assign boot_bus_ready = selected && !data_fetch;
    assign boot_sd_idle = !busy && !data_fetch && !data_pending;
    assign sd_blk_req = rst_n && state == REQUEST;
    assign sd_blk_lba = lba;
    assign sd_blk_we = 1'b0;
    assign sd_blk_tx_valid = 1'b0;
    assign sd_blk_tx_data = 8'd0;
    wire sector_full = offset == 10'd512;
    assign sd_blk_rx_ready = rst_n && state == RECEIVE && !sector_full;
    wire receive_byte = sd_blk_rx_valid && sd_blk_rx_ready;

    always @* begin
        boot_bus_rdata = 8'hff;
        if (selected && !boot_bus_we) begin
            case (port_number)
                PORT_LBA0: boot_bus_rdata = lba[7:0];
                PORT_LBA1: boot_bus_rdata = lba[15:8];
                PORT_LBA2: boot_bus_rdata = lba[23:16];
                PORT_LBA3: boot_bus_rdata = lba[31:24];
                PORT_CONTROL: boot_bus_rdata = sd_owner_boot ?
                              {error, 1'b0, available, done, busy} : 8'd0;
                PORT_DATA: if (data_take) boot_bus_rdata = sector_byte;
                default: boot_bus_rdata = 8'hff;
            endcase
        end
    end

    // Capture and firmware reads use the same address in separate phases.
    always @(posedge clk_sys) begin
        if (receive_byte)
            sector_buffer[offset[8:0]] <= sd_blk_rx_data;
        if (data_fetch)
            sector_byte <= sector_buffer[offset[8:0]];
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            lba <= 32'd0;
            offset <= 10'd0;
            done <= 1'b0;
            data_valid <= 1'b0;
            error <= 4'd0;
            data_pending <= 1'b0;
        end else begin
            data_pending <= data_fetch;
            if (register_write) begin
                case (port_number)
                    PORT_LBA0: lba[7:0] <= boot_bus_wdata;
                    PORT_LBA1: lba[15:8] <= boot_bus_wdata;
                    PORT_LBA2: lba[23:16] <= boot_bus_wdata;
                    PORT_LBA3: lba[31:24] <= boot_bus_wdata;
                    default: ;
                endcase
            end

            if (start) begin
                state <= REQUEST;
                offset <= 10'd0;
                done <= 1'b0;
                data_valid <= 1'b0;
                error <= 4'd0;
            end else if (state == REQUEST && sd_blk_ready) begin
                state <= RECEIVE;
            end else if (state == RECEIVE && sd_blk_done) begin
                state <= IDLE;
                offset <= 10'd0;
                done <= 1'b1;
                data_valid <= sector_full && sd_blk_error == 4'd0;
                error <= !sector_full && sd_blk_error == 4'd0 ? ERROR_IO : sd_blk_error;
            end else if (receive_byte || data_take) begin
                offset <= offset + 1'b1;
                if (data_take && offset == 10'd511)
                    data_valid <= 1'b0;
            end

            if (!sd_owner_boot) begin
                done <= 1'b0;
                data_valid <= 1'b0;
                error <= 4'd0;
            end
        end
    end
endmodule
