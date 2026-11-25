module spectrum_io (
    input  wire        clk_sys,
    input  wire        reset_n,
    input  wire [15:0] addr,
    input  wire [4:0]  wdata,
    input  wire        cycle_done,
    input  wire        write_cycle,
    input  wire        is_tk,
    input  wire        is_plus3,
    input  wire        paging_locked,
    input  wire [7:0]  floating_bus,
    input  wire [7:0]  asic_bus,
    input  wire [39:0] key_matrix_n,
    input  wire [5:0]  joy1,
    input  wire [5:0]  joy2,
    input  wire [1:0]  cfg_input_map_id,
    input  wire [1:0]  cfg_joy1_b_map,
    input  wire [1:0]  cfg_joy2_b_map,
    input  wire        ear_bit,
    output reg  [2:0]  border,
    output reg         mic_bit,
    output reg         beeper_bit,
    input  wire        cfg_psg_enable,
    output wire        ay_req,
    output wire [1:0]  ay_op,
    input  wire [7:0]  ay_rdata,
    input  wire        plus3_disk,
    input  wire        beta_active,
    output wire        disk_req,
    output wire        disk_we,
    output reg  [2:0]  disk_reg,
    input  wire [7:0]  disk_rdata,
    output reg  [7:0]  rdata
);
    wire fe_select = !addr[0];
    wire ay_port = cfg_psg_enable && addr[15] && !addr[1];
    wire ay_read = ay_port && (addr[14] || is_plus3);
    assign ay_req = cycle_done && (write_cycle ? ay_port : ay_read);
    assign ay_op = !ay_req ? 2'd0 : !write_cycle ? 2'd2 : {1'b0, !addr[14]};

    wire both_sinclair = cfg_input_map_id == 2'd0;
    wire kempston = cfg_input_map_id == 2'd1;
    wire use_joysticks = both_sinclair || kempston;
    wire [5:0] kempston_data = {joy1[5] && cfg_joy1_b_map == 2'd3,
                               joy1[4], joy1[0], joy1[1], joy1[2], joy1[3]};
    reg [39:0] keys_n;
    reg [4:0] selected_keys;
    integer row;
    always @* begin
        keys_n = key_matrix_n;
        if (both_sinclair)
            keys_n[24:20] = keys_n[24:20] & ~{joy1[2], joy1[3], joy1[1], joy1[0], joy1[4]};
        if (use_joysticks) begin
            keys_n[19:15] = keys_n[19:15] & ~{joy2[4], joy2[0], joy2[1], joy2[3], joy2[2]};
            keys_n[35] = keys_n[35] && !((joy1[5] && cfg_joy1_b_map == 2'd1) ||
                                         (joy2[5] && cfg_joy2_b_map == 2'd1));
            keys_n[36] = keys_n[36] && !((joy1[5] && cfg_joy1_b_map == 2'd2) ||
                                         (joy2[5] && cfg_joy2_b_map == 2'd2));
        end
        selected_keys = 5'h1f;
        for (row = 0; row < 8; row = row + 1)
            if (!addr[8 + row])
                selected_keys = selected_keys & keys_n[5 * row +: 5];
    end

    reg disk_selected;
    always @* begin
        disk_selected = 1'b0;
        disk_reg = 3'd0;
        if (plus3_disk) begin
            case (addr & 16'hf002)
                16'h2000: disk_selected = !write_cycle;
                16'h3000: begin
                    disk_selected = 1'b1;
                    disk_reg = 3'd1;
                end
                default: begin end
            endcase
        end else if (beta_active) begin
            disk_selected = addr[4:0] == 5'h1f;
            disk_reg = (&addr[7:5]) ? 3'd4 : {1'b0, addr[6:5]};
            disk_selected = disk_selected && (!addr[7] || (&addr[7:5]));
        end
    end

    assign disk_req = cycle_done && disk_selected;
    assign disk_we = disk_req && write_cycle;

    always @* begin
        if (is_plus3)
            rdata = !paging_locked && (addr & 16'hf003) == 16'h0001 ?
                    (asic_bus | 8'h01) : 8'hff;
        else
            rdata = floating_bus;

        if (fe_select)
            rdata = {!is_tk, ear_bit, !is_tk || floating_bus[5], selected_keys};
        else if (kempston && addr[7:0] == 8'h1f)
            rdata = {2'b00, kempston_data};
        if (ay_read)
            rdata = ay_rdata;
        if (disk_selected)
            rdata = disk_rdata;
    end

    always @(posedge clk_sys or negedge reset_n) begin
        if (!reset_n) begin
            border <= 3'd0;
            mic_bit <= 1'b0;
            beeper_bit <= 1'b0;
        end else if (cycle_done && write_cycle && fe_select) begin
            border <= wdata[2:0];
            mic_bit <= wdata[3];
            beeper_bit <= wdata[4];
        end
    end
endmodule
