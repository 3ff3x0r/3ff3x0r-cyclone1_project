module video_scandoubler (
    input  wire       clk_sys,
    input  wire       rst_n,
    input  wire       ula_px_ce,
    input  wire [3:0] ula_color,
    input  wire [9:0] ula_x,
    input  wire [8:0] ula_y,
    input  wire       ula_hs_n,
    input  wire       ula_vs_n,
    input  wire       ula_blank,
    input  wire       loader_diag_active,
    input  wire [7:0] loader_diag_code,
    input  wire       clk_vga,
    input  wire       rst_vga_n,
    output reg  [5:0] vga_r,
    output reg  [5:0] vga_g,
    output reg  [5:0] vga_b,
    output reg        vga_hs_n,
    output reg        vga_vs_n,
    output reg        vga_blank
);
    localparam [3:0] BLANK_PIXEL = 4'b1000;
    localparam [14:0] END_MARGIN = 15'd6;

    // Flush both ends of the line transfer on either reset. Release each
    // end on its own clock, even when only the other domain was reset.
    wire raster_reset_n = rst_n && rst_vga_n;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg sys_reset_meta;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg vga_reset_meta;
    reg capture_reset_n;
    reg scan_reset_n;
    always @(posedge clk_sys or negedge raster_reset_n) begin
        if (!raster_reset_n) begin
            sys_reset_meta <= 1'b0;
            capture_reset_n <= 1'b0;
        end else begin
            sys_reset_meta <= 1'b1;
            capture_reset_n <= sys_reset_meta;
        end
    end
    always @(posedge clk_vga or negedge raster_reset_n) begin
        if (!raster_reset_n) begin
            vga_reset_meta <= 1'b0;
            scan_reset_n <= 1'b0;
        end else begin
            vga_reset_meta <= 1'b1;
            scan_reset_n <= vga_reset_meta;
        end
    end

    reg capturing;
    reg write_bank;
    reg [9:0] last_x;
    reg hs_initial_n;
    reg hs_previous_n;
    reg [9:0] hs_edge_a;
    reg [9:0] hs_edge_b;
    reg vs_initial_n;
    reg visible_line;
    reg [9:0] visible_x;
    reg [3:0] visible_row;
    reg [8:0] frame_diag;

    reg [9:0] ready_last_x;
    reg ready_hs_n;
    reg [9:0] ready_hs_edge_a;
    reg [9:0] ready_hs_edge_b;
    reg ready_vs_n;
    reg [9:0] ready_visible_x;
    reg [3:0] ready_visible_row;
    reg [8:0] ready_diag;

    wire starts_line = (ula_x == 10'd0);
    wire write_pixel = capture_reset_n && ula_px_ce && (capturing || starts_line);
    wire pixel_write_bank = write_bank ^ starts_line;
    // Blanking has its own code without widening either RAM. Both incoming
    // black encodings collapse to ordinary black on visible pixels.
    wire [3:0] write_color = ula_blank ? BLANK_PIXEL :
                             (ula_color[2:0] == 3'd0 ? 4'd0 : ula_color);
    reg [9:0] read_x;

    (* ramstyle = "M4K, no_rw_check" *) reg [3:0] line_a [0:1023];
    (* ramstyle = "M4K, no_rw_check" *) reg [3:0] line_b [0:1023];
    reg [9:0] ram_address;
    reg [3:0] pixel_a;
    reg [3:0] pixel_b;

    always @(posedge clk_sys) begin
        if (write_pixel && !pixel_write_bank)
            line_a[ula_x] <= write_color;
        if (write_pixel && pixel_write_bank)
            line_b[ula_x] <= write_color;
    end
    always @(posedge clk_vga) begin
        ram_address <= read_x;
        pixel_a <= line_a[ram_address];
        pixel_b <= line_b[ram_address];
    end

    // Line starts alternate the write bank and publish the previous line.
    // HS can wrap around x=0, so record its initial level and both edges.
    // Sample VS at x=0 to keep one continuous pulse across doubled lines.
    always @(posedge clk_sys or negedge capture_reset_n) begin
        if (!capture_reset_n) begin
            capturing <= 1'b0;
            write_bank <= 1'b1;
            last_x <= 10'd0;
            hs_initial_n <= 1'b1;
            hs_previous_n <= 1'b1;
            hs_edge_a <= 10'd0;
            hs_edge_b <= 10'd0;
            vs_initial_n <= 1'b1;
            visible_line <= 1'b0;
            visible_x <= 10'd0;
            visible_row <= 4'd0;
            frame_diag <= 9'd0;
            ready_last_x <= 10'd0;
            ready_hs_n <= 1'b1;
            ready_hs_edge_a <= 10'd0;
            ready_hs_edge_b <= 10'd0;
            ready_vs_n <= 1'b1;
            ready_visible_x <= 10'd0;
            ready_visible_row <= 4'd8;
            ready_diag <= 9'd0;
        end else if (ula_px_ce) begin
            if (starts_line) begin
                capturing <= 1'b1;
                write_bank <= ~write_bank;
                ready_last_x <= last_x;
                ready_hs_n <= hs_initial_n;
                ready_hs_edge_a <= hs_edge_a;
                ready_hs_edge_b <= hs_edge_b;
                ready_vs_n <= vs_initial_n;
                ready_visible_x <= visible_x;
                ready_visible_row <= visible_row;
                ready_diag <= frame_diag;

                last_x <= 10'd0;
                hs_initial_n <= ula_hs_n;
                hs_previous_n <= ula_hs_n;
                hs_edge_a <= 10'd0;
                hs_edge_b <= 10'd0;
                vs_initial_n <= ula_vs_n;
                visible_line <= !ula_blank;
                visible_x <= 10'd0;
                if (ula_y == 9'd0) begin
                    visible_row <= 4'd0;
                    frame_diag <= {loader_diag_active, loader_diag_code};
                end else if (visible_line && (visible_row < 4'd8)) begin
                    visible_row <= visible_row + 4'd1;
                end
            end else if (capturing) begin
                last_x <= ula_x;
                hs_previous_n <= ula_hs_n;
                if (hs_previous_n != ula_hs_n) begin
                    if (hs_edge_a == 10'd0)
                        hs_edge_a <= ula_x;
                    else
                        hs_edge_b <= ula_x;
                end
                if (!visible_line && !ula_blank) begin
                    visible_line <= 1'b1;
                    visible_x <= ula_x;
                end
            end
        end
    end

    // The registered ready_* descriptor is held for a full guest line.
    // Its only capture is on the edge after the two-flop bank synchronizer
    // changes. Constrain the bundled paths to settle within two clk_vga
    // periods (with setup margin) when integrating independent clocks.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [1:0] bank_sync;
    reg bank_seen;
    reg have_line_start;
    reg [14:0] line_age;

    always @(posedge clk_vga or negedge scan_reset_n) begin
        if (!scan_reset_n)
            bank_sync <= 2'b11;
        else
            bank_sync <= {bank_sync[0], write_bank};
    end

    wire line_arrived = bank_sync[1] != bank_seen;
    wire raster_timeout = &line_age;
    wire [14:0] measured_half = {1'b0, line_age[14:1]};
    wire [10:0] ready_width = {1'b0, ready_last_x} + 11'd1;
    wire [14:0] min_half = {4'd0, ready_width} + END_MARGIN;

    reg scan_valid;
    reg second_copy;
    reg scan_bank;
    reg [9:0] scan_last_x;
    reg [10:0] scan_width;
    reg [14:0] half_period;
    reg [14:0] pixel_wrap_at;
    reg [14:0] pixel_phase;
    reg scan_hs_n;
    reg [9:0] scan_hs_edge_a;
    reg [9:0] scan_hs_edge_b;
    reg scan_vs_n;
    reg [9:0] scan_visible_x;
    reg [3:0] scan_visible_row;
    reg [8:0] scan_diag;
    reg issue_pixel;

    wire [15:0] reduced_phase = {1'b0, pixel_phase} - {1'b0, pixel_wrap_at};
    wire next_pixel = !reduced_phase[15];
    wire next_copy = !second_copy && (line_age == half_period);

    // Anchor each pair to the incoming line and start the second copy at
    // the measured half-line. Distribute pixels over each half with an
    // accumulator. Hold the final pixel for the last six VGA cycles, plus
    // any boundary quantization, so a buffer's useful reads finish ahead
    // of reuse. The VGA clock must fit all pixels in this budget (16 MHz
    // or faster for the native rasters) and line periods must be stable.
    always @(posedge clk_vga or negedge scan_reset_n) begin
        if (!scan_reset_n) begin
            bank_seen <= 1'b1;
            have_line_start <= 1'b0;
            line_age <= 15'd1;
            scan_valid <= 1'b0;
            second_copy <= 1'b0;
            scan_bank <= 1'b0;
            read_x <= 10'd0;
            scan_last_x <= 10'd0;
            scan_width <= 11'd0;
            half_period <= 15'd0;
            pixel_wrap_at <= 15'd0;
            pixel_phase <= 15'd0;
            scan_hs_n <= 1'b1;
            scan_hs_edge_a <= 10'd0;
            scan_hs_edge_b <= 10'd0;
            scan_vs_n <= 1'b1;
            scan_visible_x <= 10'd0;
            scan_visible_row <= 4'd8;
            scan_diag <= 9'd0;
            issue_pixel <= 1'b0;
        end else begin
            issue_pixel <= 1'b0;
            if (!raster_timeout)
                line_age <= line_age + 15'd1;
            if (line_arrived) begin
                bank_seen <= bank_sync[1];
                have_line_start <= 1'b1;
                line_age <= 15'd1;
                scan_valid <= have_line_start && !raster_timeout && (measured_half >= min_half);
                second_copy <= 1'b0;
                scan_bank <= ~bank_sync[1];
                read_x <= 10'd0;
                scan_last_x <= ready_last_x;
                scan_width <= ready_width;
                half_period <= measured_half;
                pixel_wrap_at <= measured_half - min_half;
                pixel_phase <= 15'd0;
                scan_hs_n <= ready_hs_n;
                scan_hs_edge_a <= ready_hs_edge_a;
                scan_hs_edge_b <= ready_hs_edge_b;
                scan_vs_n <= ready_vs_n;
                scan_visible_x <= ready_visible_x;
                scan_visible_row <= ready_visible_row;
                scan_diag <= ready_diag;
                issue_pixel <= 1'b1;
            end else if (raster_timeout) begin
                scan_valid <= 1'b0;
            end else if (scan_valid) begin
                if (next_copy) begin
                    second_copy <= 1'b1;
                    read_x <= 10'd0;
                    pixel_phase <= 15'd0;
                    issue_pixel <= 1'b1;
                end else if (read_x != scan_last_x) begin
                    pixel_phase <= next_pixel ? reduced_phase[14:0] :
                                               pixel_phase + {4'd0, scan_width};
                    if (next_pixel) begin
                        read_x <= read_x + 10'd1;
                        issue_pixel <= 1'b1;
                    end
                end
            end
        end
    end

    // The first eight visible guest lines carry eight MSB-first lamps.
    // White outlines frame amber ones and blue zeros on a black strip.
    wire [9:0] lamp_x = read_x - scan_visible_x;
    wire [2:0] lamp_bit = 3'd7 - lamp_x[6:4];
    wire [3:0] lamp_column = lamp_x[3:0];
    wire [7:0] diag_code = scan_diag[7:0];
    wire lamp_strip = scan_diag[8] && (scan_visible_row < 4'd8) &&
                      (read_x >= scan_visible_x) && (lamp_x < 10'd128);
    reg [3:0] lamp_color;

    always @* begin
        if ((lamp_column == 4'd0) || (lamp_column >= 4'd13))
            lamp_color = 4'd0;
        else if ((scan_visible_row == 4'd0) || (scan_visible_row == 4'd7) ||
                 (lamp_column == 4'd1) || (lamp_column == 4'd12))
            lamp_color = 4'b1111;
        else
            lamp_color = diag_code[lamp_bit] ? 4'b1110 : 4'b1001;
    end

    wire read_hs_n = scan_hs_n ^
                     ((scan_hs_edge_a != 10'd0) && (read_x >= scan_hs_edge_a)) ^
                     ((scan_hs_edge_b != 10'd0) && (read_x >= scan_hs_edge_b));
    reg [8:0] read_qualifiers;
    reg [8:0] pixel_qualifiers;
    wire pixel_update, pixel_bank, pixel_hs_n, pixel_vs_n, pixel_lamp;
    wire [3:0] pixel_lamp_color;
    assign {pixel_update, pixel_bank, pixel_hs_n, pixel_vs_n, pixel_lamp, pixel_lamp_color} =
           pixel_qualifiers;

    // Align the pixel qualifiers with the unconditional synchronous RAM
    // reads. Only the selected bank and issued addresses reach the DAC.
    always @(posedge clk_vga or negedge scan_reset_n) begin
        if (!scan_reset_n) begin
            read_qualifiers <= 9'd0;
            pixel_qualifiers <= 9'd0;
        end else begin
            read_qualifiers <= {scan_valid && issue_pixel, scan_bank, read_hs_n,
                                scan_vs_n, lamp_strip, lamp_color};
            pixel_qualifiers <= read_qualifiers;
        end
    end

    wire [3:0] raster_pixel = pixel_bank ? pixel_b : pixel_a;
    wire is_blank = raster_pixel == BLANK_PIXEL;
    wire [3:0] dac_color = pixel_lamp ? pixel_lamp_color : raster_pixel;
    wire [5:0] intensity = dac_color[3] ? 6'd63 : 6'd47;
    wire show_rgb = scan_valid && !is_blank;

    always @(posedge clk_vga or negedge scan_reset_n) begin
        if (!scan_reset_n) begin
            {vga_r, vga_g, vga_b} <= 18'd0;
            vga_hs_n <= 1'b1;
            vga_vs_n <= 1'b1;
            vga_blank <= 1'b1;
        end else if (pixel_update || !scan_valid) begin
            vga_hs_n <= !scan_valid || pixel_hs_n;
            vga_vs_n <= !scan_valid || pixel_vs_n;
            vga_blank <= !scan_valid || is_blank;
            vga_r <= (show_rgb && dac_color[1]) ? intensity : 6'd0;
            vga_g <= (show_rgb && dac_color[2]) ? intensity : 6'd0;
            vga_b <= (show_rgb && dac_color[0]) ? intensity : 6'd0;
        end
    end
endmodule
