module spectrum_mmu (
    input  wire        clk_sys,
    input  wire        reset_n,
    input  wire [2:0]  paging_id,
    input  wire [3:0]  rom_valid_mask,
    input  wire [15:0] addr,
    input  wire        port_write,
    input  wire [5:0]  port_data,
    input  wire        beta_enable,
    input  wire        opcode_read,
    output reg         is_ram,
    output reg  [2:0]  ram_bank,
    output wire        mapped,
    output wire [21:0] physical_addr,
    output wire        screen_bank7,
    output wire        paging_locked,
    output wire        disk_motor,
    output wire        beta_active
);
    reg [5:0] page_7ffd;
    reg [3:0] page_1ffd;
    reg beta_rom;
    reg opcode_seen;

    wire plus3 = paging_id == 3'd3;
    wire pentagon = paging_id == 3'd4;
    wire paged = paging_id == 3'd2 || plus3 || pentagon;
    wire all_ram = plus3 && page_1ffd[0];
    wire select_7ffd = plus3 ? ((addr & 16'hc002) == 16'h4000) :
                               ((addr & 16'h8002) == 16'h0000);
    wire select_1ffd = (addr & 16'hf002) == 16'h1000;
    wire beta_entry = beta_enable && page_7ffd[4] && addr[15:8] == 8'h3d;
    wire beta_exit = addr[15:14] != 2'b00;
    wire [1:0] rom_slot = beta_active ? 2'd2 :
                          {plus3 && page_1ffd[2], paged && page_7ffd[4]};

    assign beta_active = beta_enable &&
                         (opcode_read ? (!beta_exit && (beta_rom || beta_entry)) : beta_rom);
    assign screen_bank7 = paged && page_7ffd[3];
    assign paging_locked = page_7ffd[5];
    assign disk_motor = plus3 && page_1ffd[3];
    assign mapped = is_ram || ((addr[15:14] == 2'b00) && rom_valid_mask[rom_slot]);
    assign physical_addr = is_ram ? {5'd0, ram_bank, addr[13:0]} :
                                    {6'd2, rom_slot, addr[13:0]};

    always @(posedge clk_sys or negedge reset_n) begin
        if (!reset_n) begin
            page_7ffd <= 6'd0;
            page_1ffd <= 4'd0;
            beta_rom <= 1'b0;
            opcode_seen <= 1'b0;
        end else begin
            if (port_write && plus3 && select_1ffd && !paging_locked)
                page_1ffd <= port_data[3:0];
            if (port_write && paged && select_7ffd && !paging_locked && !beta_active)
                page_7ffd <= port_data;

            opcode_seen <= opcode_read;
            if (opcode_read && !opcode_seen)
                beta_rom <= beta_active;
        end
    end

    always @* begin
        is_ram = 1'b1;
        ram_bank = 3'd0;
        if (all_ram) begin
            case (addr[15:14])
                2'd0: ram_bank = (page_1ffd[2:1] == 2'd0) ? 3'd0 : 3'd4;
                2'd1: begin
                    case (page_1ffd[2:1])
                        2'd0: ram_bank = 3'd1;
                        2'd3: ram_bank = 3'd7;
                        default: ram_bank = 3'd5;
                    endcase
                end
                2'd2: ram_bank = (page_1ffd[2:1] == 2'd0) ? 3'd2 : 3'd6;
                2'd3: ram_bank = (page_1ffd[2:1] == 2'd1) ? 3'd7 : 3'd3;
            endcase
        end else begin
            case (addr[15:14])
                2'd0: is_ram = 1'b0;
                2'd1: ram_bank = 3'd5;
                2'd2: begin
                    is_ram = paging_id != 3'd0;
                    ram_bank = 3'd2;
                end
                2'd3: begin
                    is_ram = paging_id != 3'd0;
                    ram_bank = paged ? page_7ffd[2:0] : 3'd0;
                end
            endcase
        end
    end
endmodule
