module spectrum_ula (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire        run,
    input  wire        ce_cpu,
    input  wire        ce_ula,
    input  wire [2:0]  timing_id,
    input  wire [2:0]  border,
    input  wire        screen_bank7,
    output wire        screen_rd_req,
    output wire        screen_rd_bank7,
    output wire [12:0] screen_rd_offset,
    input  wire        screen_rd_valid,
    input  wire [7:0]  screen_rd_data,
    output wire        ula_px_ce,
    output wire [3:0]  ula_color,
    output reg  [9:0]  ula_x,
    output reg  [8:0]  ula_y,
    output wire        ula_hs_n,
    output wire        ula_vs_n,
    output wire        ula_blank,
    output wire        int_n,
    input  wire        ula_bus_valid,
    input  wire        ula_bus_is_ram,
    input  wire [2:0]  ula_bus_ram_bank,
    input  wire [2:0]  ula_contend_id,
    input  wire        contended_transfer,
    input  wire [7:0]  transfer_data,
    output reg         bus_contended,
    output reg  [2:0]  raster_delay,
    output wire [7:0]  floating_bus,
    output wire [7:0]  asic_bus
);
    reg [9:0] line_pixels;
    reg [8:0] lines, picture_y, vs_y;
    reg [9:0] blank_x, hs_x, bus_start_x, picture_x, int_x;
    reg [8:0] int_y;
    reg [9:0] int_width;
    reg running;
    reg flash_phase;
    reg [3:0] flash_count;

    // Coordinates start at the top-left visible border. Bus slots have
    // their own phase relative to the picture and the interrupt.
    always @* begin
        line_pixels = 10'd448;
        lines = 9'd312;
        picture_y = 9'd56;
        blank_x = 10'd344;
        hs_x = 10'd368;
        vs_y = 9'd296;
        bus_start_x = 10'd52;
        picture_x = 10'd48;
        int_y = 9'd304;
        int_x = 10'd48;
        int_width = 10'd64;
        case (timing_id)
            3'd1, 3'd2: begin
                line_pixels = 10'd456;
                lines = 9'd311;
                hs_x = 10'd372;
                vs_y = 9'd296;
                int_x = timing_id == 3'd2 ? 10'd46 : 10'd52;
                int_width = timing_id == 3'd2 ? 10'd64 : 10'd72;
            end
            3'd3, 3'd4: begin
                line_pixels = 10'd456;
                lines = timing_id == 3'd4 ? 9'd262 : 9'd312;
                picture_y = timing_id == 3'd4 ? 9'd32 : 9'd56;
                blank_x = 10'd360;
                hs_x = 10'd380;
                vs_y = timing_id == 3'd4 ? 9'd256 : 9'd304;
                bus_start_x = 10'd57;
                picture_x = 10'd52;
                int_y = timing_id == 3'd4 ? 9'd255 : 9'd303;
                int_x = 10'd315;
            end
            3'd5: begin
                lines = 9'd320;
                picture_y = 9'd64;
                blank_x = 10'd340;
                hs_x = 10'd366;
                vs_y = 9'd312;
                bus_start_x = 10'd44;
                picture_x = 10'd44;
                int_y = 9'd303;
                int_x = 10'd356;
                int_width = 10'd72;
            end
            default: begin end
        endcase
    end

    wire last_x = ula_x == line_pixels - 10'd1;
    wire last_y = ula_y == lines - 9'd1;
    wire is_tk = timing_id == 3'd3 || timing_id == 3'd4;
    wire [8:0] vblank_len = is_tk || timing_id == 3'd5 ? 9'd8 : 9'd4;
    assign ula_px_ce = rst_n && run && ce_ula && (running || !ce_cpu);
    assign ula_hs_n = !(ula_x >= hs_x && ula_x < hs_x + 10'd32);
    assign ula_vs_n = !(ula_y >= vs_y && ula_y < vs_y + (timing_id == 3'd5 ? 9'd8 : 9'd4));
    assign ula_blank = ula_x >= blank_x || (ula_y >= vs_y && ula_y < vs_y + vblank_len);
    assign int_n = !run || !(ula_y == int_y && ula_x >= int_x && ula_x < int_x + int_width);

    wire [8:0] row = ula_y - picture_y;
    wire picture_line = row < 9'd192;
    wire [9:0] draw_x = ula_x - picture_x;
    wire [9:0] bus_x = ula_x - bus_start_x;
    // Prefetch each pair of cells eight pixels before it is drawn. The
    // externally visible bus phase is independent of the mirror read.
    wire [9:0] request_x = draw_x + 10'd8;
    wire [4:0] column = {request_x[7:4], request_x[2]};
    assign screen_rd_req = ula_px_ce && picture_line && request_x < 10'd256 &&
                           !request_x[3] && !request_x[0];
    assign screen_rd_bank7 = screen_bank7;
    assign screen_rd_offset = request_x[1] ? {3'b110, row[7:3], column} :
                                              {row[7:6], row[2:0], row[5:3], column};

    reg [1:0] read_pending;
    reg [1:0] read_slot, capture_slot;
    wire capture_read = read_pending[1] && screen_rd_valid;
    reg [7:0] bitmap_even, bitmap_odd, attr_even, attr_odd;
    reg [15:0] pixel_pair;
    reg [7:0] active_attr_even, active_attr_odd;
    reg [7:0] last_asic_bus;
    wire [7:0] attr = draw_x[3] ? active_attr_odd : active_attr_even;
    wire ink = pixel_pair[~draw_x[3:0]] ^ (attr[7] && flash_phase);
    wire float_active = picture_line && bus_x < 10'd256 && !bus_x[3];
    wire [7:0] video_bus = bus_x[2] ?
                           (bus_x[1] ? active_attr_odd : pixel_pair[7:0]) :
                           (bus_x[1] ? active_attr_even : pixel_pair[15:8]);
    wire video_transfer = ula_px_ce && float_active && !bus_x[0];
    assign ula_color = ula_blank ? 4'd0 :
                       picture_line && draw_x < 10'd256 ?
                           {attr[6], ink ? attr[2:0] : attr[5:3]} : {1'b0, border};
    assign floating_bus = float_active ? video_bus : 8'hff;
    assign asic_bus = video_transfer ? video_bus : last_asic_bus;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            running <= 1'b0;
            ula_x <= 10'd0;
            ula_y <= 9'd0;
            flash_phase <= 1'b0;
            flash_count <= 4'd0;
            read_pending <= 2'b0;
            read_slot <= 2'd0;
            capture_slot <= 2'd0;
            bitmap_even <= 8'd0;
            bitmap_odd <= 8'd0;
            attr_even <= 8'd0;
            attr_odd <= 8'd0;
            pixel_pair <= 16'd0;
            active_attr_even <= 8'd0;
            active_attr_odd <= 8'd0;
            last_asic_bus <= 8'hff;
        end else if (!run) begin
            running <= 1'b0;
            ula_x <= 10'd0;
            ula_y <= 9'd0;
            flash_phase <= 1'b0;
            flash_count <= 4'd0;
            read_pending <= 2'b0;
            last_asic_bus <= 8'hff;
        end else begin
            // Keep the destination tag aligned with the registered mirror byte.
            read_pending <= {read_pending[0], screen_rd_req};
            if (screen_rd_req)
                read_slot <= request_x[2:1];
            if (read_pending[0])
                capture_slot <= read_slot;
            if (capture_read) begin
                case (capture_slot)
                    2'd0: bitmap_even <= screen_rd_data;
                    2'd1: attr_even <= screen_rd_data;
                    2'd2: bitmap_odd <= screen_rd_data;
                    2'd3: attr_odd <= screen_rd_data;
                endcase
            end
            if (contended_transfer)
                last_asic_bus <= transfer_data;
            else if (video_transfer)
                last_asic_bus <= video_bus;

            if (ula_px_ce) begin
                running <= 1'b1;
                if (last_x) begin
                    ula_x <= 10'd0;
                    ula_y <= last_y ? 9'd0 : ula_y + 9'd1;
                    if (last_y) begin
                        flash_count <= flash_count + 4'd1;
                        if (&flash_count)
                            flash_phase <= !flash_phase;
                    end
                end else begin
                    ula_x <= ula_x + 10'd1;
                end
                if (picture_line && draw_x[3:0] == 4'd15 &&
                    (draw_x == 10'h3ff || draw_x < 10'd255)) begin
                    pixel_pair <= {bitmap_even, bitmap_odd};
                    active_attr_even <= attr_even;
                    // At two fabric clocks per pixel the final attribute
                    // can arrive on the pixel-pair load edge itself.
                    active_attr_odd <= capture_read && capture_slot == 2'd3 ?
                                       screen_rd_data : attr_odd;
                end
            end
        end
    end

    // Lookup at the nominal T1 edge. The phase is relative to each line,
    // so a 228-T-state line does not rotate the eight-state pattern.
    wire [9:0] contend_x = ula_contend_id == 3'd3 ? ula_x - 10'd40 :
                            is_tk ? ula_x - 10'd42 : ula_x - 10'd46;
    wire [2:0] phase = contend_x[3:1];
    always @* begin
        bus_contended = 1'b0;
        raster_delay = 3'd0;
        case (ula_contend_id)
            3'd1, 3'd4, 3'd5: bus_contended = ula_bus_ram_bank == 3'd5;
            3'd2: bus_contended = ula_bus_ram_bank[0];
            3'd3: bus_contended = ula_bus_ram_bank[2];
            default: begin end
        endcase
        bus_contended = bus_contended && ula_bus_valid && ula_bus_is_ram;
        if (picture_line && contend_x < 10'd256) begin
            case (ula_contend_id)
                3'd1, 3'd2, 3'd4, 3'd5:
                    raster_delay = phase < 3'd6 ? 3'd6 - phase : 3'd0;
                3'd3: raster_delay = 3'd1 - phase;
                default: begin end
            endcase
        end
    end
endmodule
