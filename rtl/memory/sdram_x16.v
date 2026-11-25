// Closed-page, single-byte SDR SDRAM controller. Timing parameters are in ps
// unless named in cycles. Defaults target the board's ~85.909 MHz clock and
// the commercial/industrial Micron MT48LC16M16A2.
module sdram_x16 #(
    parameter ROW_BITS = 13,
    parameter COL_BITS = 9,
    parameter BANK_BITS = 2,
    parameter CLK_PERIOD_PS = 11640,
    parameter POWERUP_CYCLES = (100000000 + CLK_PERIOD_PS - 1) / CLK_PERIOD_PS,
    parameter T_RCD_PS = 20000,
    parameter T_RP_PS = 20000,
    parameter T_RFC_PS = 66000,
    parameter T_RAS_PS = 44000,
    parameter T_RC_PS = 66000,
    parameter T_WR_EXTRA_PS = 7500,
    parameter REFRESH_INTERVAL_PS = 7812500
) (
    input  wire        clk_sys,
    input  wire        rst_n,
    output reg         initialized,
    input  wire        req,
    output wire        accept,
    input  wire [21:0] addr,
    input  wire        we,
    input  wire [7:0]  wdata,
    output reg         rvalid,
    output reg  [7:0]  rdata,
    output wire        user_busy,
    output wire        write_commit,
    output wire [21:0] write_addr,
    output wire [7:0]  write_data,
    output reg         sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output reg  [12:0] sdram_a,
    output reg  [1:0]  sdram_ba,
    output reg  [1:0]  sdram_dqm,
    inout  wire [15:0] sdram_dq
);

    function integer cycles;
        input integer picoseconds;
        begin
            cycles = (picoseconds + CLK_PERIOD_PS - 1) / CLK_PERIOD_PS;
        end
    endfunction

    function integer max_cycles;
        input integer a;
        input integer b;
        begin
            max_cycles = (a > b) ? a : b;
        end
    endfunction

    function integer counter_bits;
        input integer largest;
        integer remaining;
        begin
            remaining = largest;
            counter_bits = 1;
            while (remaining > 1) begin
                remaining = remaining >> 1;
                counter_bits = counter_bits + 1;
            end
        end
    endfunction

    localparam T_RCD = cycles(T_RCD_PS);
    localparam T_RP  = cycles(T_RP_PS);
    localparam T_RFC = cycles(T_RFC_PS);
    localparam T_RAS = cycles(T_RAS_PS);
    localparam T_RC  = cycles(T_RC_PS);
    localparam T_WR  = 1 + cycles(T_WR_EXTRA_PS);
    localparam T_MRD = 3;
    localparam CAS_LATENCY = 3;
    // The PLL clocks SDRAM just before clk_sys. A command launched on
    // clk_sys reaches the next SDRAM edge. DQ appears after the CAS edge
    // and is captured on the clk_sys edge just after the next SDRAM edge.
    localparam READ_CAPTURE = CAS_LATENCY + 2;
    localparam MIN_ACCESS_TO_PRE = max_cycles(T_RAS, T_RC - T_RP) - T_RCD;
    localparam WRITE_TO_PRE = max_cycles(T_WR, MIN_ACCESS_TO_PRE);
    // A one-word SDR read can precharge starting one edge after READ.
    // Keep the DQ capture independent so tRP overlaps the CAS latency.
    localparam READ_TO_PRE = max_cycles(1, MIN_ACCESS_TO_PRE);

    localparam REFRESH_LIMIT = REFRESH_INTERVAL_PS / CLK_PERIOD_PS;
    // Stop dispatch early enough for the longest admitted operation to close
    // its bank and satisfy tRP before the refresh deadline.
    localparam REFRESH_GUARD = 2 + T_RCD + T_RP
        + max_cycles(WRITE_TO_PRE, READ_TO_PRE);
    localparam REFRESH_DUE = REFRESH_LIMIT - REFRESH_GUARD;
    localparam REFRESH_BITS = counter_bits(REFRESH_LIMIT);
    localparam DELAY_MAX = max_cycles(max_cycles(T_RFC, T_MRD),
        max_cycles(max_cycles(T_RCD, T_RP), max_cycles(WRITE_TO_PRE, READ_TO_PRE)));
    localparam DELAY_BITS = counter_bits(DELAY_MAX);
    localparam POWER_BITS = counter_bits(POWERUP_CYCLES);
    localparam [POWER_BITS-1:0] POWER_WAIT = POWERUP_CYCLES[POWER_BITS-1:0] - 1'b1;
    localparam [DELAY_BITS-1:0] RCD_WAIT = T_RCD[DELAY_BITS-1:0] - 1'b1;
    localparam [DELAY_BITS-1:0] RP_WAIT = T_RP[DELAY_BITS-1:0] - 1'b1;
    localparam [DELAY_BITS-1:0] RFC_WAIT = T_RFC[DELAY_BITS-1:0] - 1'b1;
    // Report ready only after tMRD has elapsed since the SDRAM sampled MRS.
    localparam [DELAY_BITS-1:0] MRD_WAIT = T_MRD[DELAY_BITS-1:0];
    localparam [DELAY_BITS-1:0] WRITE_WAIT = WRITE_TO_PRE[DELAY_BITS-1:0] - 1'b1;
    localparam [DELAY_BITS-1:0] READ_WAIT = READ_TO_PRE[DELAY_BITS-1:0] - 1'b1;
    localparam [REFRESH_BITS-1:0] REFRESH_THRESHOLD = REFRESH_DUE[REFRESH_BITS-1:0];

    localparam [3:0] CKE_LOW      = 4'd0,
                     POWERUP      = 4'd1,
                     INIT_PRE     = 4'd2,
                     INIT_REF1    = 4'd3,
                     INIT_REF2    = 4'd4,
                     INIT_MODE    = 4'd5,
                     CLOSED       = 4'd6,
                     ACTIVATE     = 4'd7,
                     ACCESS       = 4'd8,
                     PRECHARGE    = 4'd9;

    // Active-low command pins in CS, RAS, CAS, WE order.
    localparam [3:0] CMD_DESELECT = 4'b1111,
                     CMD_PRE      = 4'b0010,
                     CMD_REF      = 4'b0001,
                     CMD_MODE     = 4'b0000,
                     CMD_ACT      = 4'b0011,
                     CMD_READ     = 4'b0101,
                     CMD_WRITE    = 4'b0100;

    reg [3:0] state;
    reg [POWER_BITS-1:0] powerup_left;
    reg [DELAY_BITS-1:0] delay_left;
    reg [REFRESH_BITS-1:0] refresh_age;
    reg [21:0] active_addr;
    reg        active_we;
    reg [7:0]  active_wdata;
    reg        transfer_pending;
    reg [READ_CAPTURE-1:0] read_pipeline;
    reg        read_high_lane;

    wire timing_done = (delay_left == 0);
    wire refresh_due = (refresh_age >= REFRESH_THRESHOLD);
    wire do_refresh = (state == CLOSED) && initialized && timing_done && refresh_due;
    wire [1:0] byte_mask = active_addr[0] ? 2'b01 : 2'b10;
    wire access_cycle = (state == ACCESS) && timing_done;
    wire read_cycle = access_cycle && !active_we;
    wire read_pending = |read_pipeline;

    // Byte address order, from MSB to LSB: row, bank, column, byte lane.
    // The 22-bit interface caps the address before geometry expansion.
    // The 4 and 8 MiB x16 configurations use 11/8/2 and 12/8/2.
    // Supported geometries have at least 21 word bits, up to 13 row bits
    // and 2 bank bits, and 8 or 9 column bits.
    localparam WORD_BITS = ROW_BITS + COL_BITS + BANK_BITS;
    wire [WORD_BITS-1:0] word_addr;
    wire [12:0] row_pins;
    wire [1:0] bank_pins;
    wire [12:0] col_pins =
        {{(13-COL_BITS){1'b0}}, word_addr[COL_BITS-1:0]};
    assign word_addr[20:0] = active_addr[21:1];
    assign row_pins[ROW_BITS-1:0] = word_addr[WORD_BITS-1:COL_BITS+BANK_BITS];
    assign bank_pins[BANK_BITS-1:0] = word_addr[COL_BITS+BANK_BITS-1:COL_BITS];

    generate
        if (WORD_BITS > 21) begin : pad_word
            assign word_addr[WORD_BITS-1:21] = 0;
        end
        if (ROW_BITS < 13) begin : pad_row
            assign row_pins[12:ROW_BITS] = 0;
        end
        if (BANK_BITS < 2) begin : pad_bank
            assign bank_pins[1:BANK_BITS] = 0;
        end
    endgenerate

    // Once DQ is captured, the arbiter can sample the previous response and
    // dispatch the next request on the same edge.
    assign accept = (state == CLOSED) && initialized && !refresh_due
        && (delay_left <= 1) && !read_pending;
    assign user_busy = transfer_pending || read_pending;
    // Retire the write on the fabric edge after SDRAM sampled the pins.
    assign write_commit = (state == PRECHARGE) && transfer_pending;
    assign write_addr = active_addr;
    assign write_data = active_wdata;

    // The board PLL drives the SDRAM clock. All pad outputs and the DQ
    // output enable register use the fabric rising edge.
    reg [3:0] pin_command;
    reg [7:0] pin_wdata;
    reg pin_dq_oe;
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = pin_command;
    assign sdram_dq = pin_dq_oe ? {pin_wdata, pin_wdata} : 16'bz;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            pin_command <= CMD_DESELECT;
            pin_wdata <= 8'b0;
            pin_dq_oe <= 1'b0;
            sdram_cke <= 1'b0;
            sdram_a <= 13'b0;
            sdram_ba <= 2'b0;
            sdram_dqm <= 2'b11;
        end else begin
            pin_command <= CMD_DESELECT;
            pin_wdata <= active_wdata;
            pin_dq_oe <= access_cycle && active_we;
            sdram_cke <= (state != CKE_LOW);
            sdram_a <= 13'b0;
            sdram_ba <= 2'b0;
            sdram_dqm <= 2'b11;

            // Read DQM takes two clocks to reach the SDRAM output buffers.
            if (read_pending)
                sdram_dqm <= read_high_lane ? 2'b01 : 2'b10;

            if (timing_done) begin
                case (state)
                    INIT_PRE: begin
                        pin_command <= CMD_PRE;
                        sdram_a[10] <= 1'b1;
                    end
                    INIT_REF1, INIT_REF2: pin_command <= CMD_REF;
                    INIT_MODE: begin
                        pin_command <= CMD_MODE;
                        // Sequential burst length 1, CL3, single write.
                        sdram_a <= 13'h230;
                    end
                    CLOSED: begin
                        if (do_refresh)
                            pin_command <= CMD_REF;
                    end
                    ACTIVATE: begin
                        pin_command <= CMD_ACT;
                        sdram_a <= row_pins;
                        sdram_ba <= bank_pins;
                    end
                    ACCESS: begin
                        pin_command <= active_we ? CMD_WRITE : CMD_READ;
                        sdram_a <= col_pins;
                        sdram_ba <= bank_pins;
                        sdram_dqm <= byte_mask;
                    end
                    PRECHARGE: begin
                        pin_command <= CMD_PRE;
                        sdram_ba <= bank_pins;
                    end
                    default: begin end
                endcase
            end
        end
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state <= CKE_LOW;
            // Keep CKE low while the clock runs for two edges.
            delay_left <= {{(DELAY_BITS-1){1'b0}}, 1'b1};
            powerup_left <= POWER_WAIT;
            refresh_age <= {REFRESH_BITS{1'b0}};
            initialized <= 1'b0;
            active_addr <= 22'b0;
            active_we <= 1'b0;
            active_wdata <= 8'b0;
            transfer_pending <= 1'b0;
            read_pipeline <= {READ_CAPTURE{1'b0}};
            read_high_lane <= 1'b0;
            rvalid <= 1'b0;
            rdata <= 8'b0;
        end else begin
            read_pipeline <= {read_pipeline[READ_CAPTURE-2:0], read_cycle};
            rvalid <= read_pipeline[READ_CAPTURE-1];
            if (read_cycle)
                read_high_lane <= active_addr[0];
            if (read_pipeline[READ_CAPTURE-1])
                rdata <= read_high_lane ? sdram_dq[15:8] : sdram_dq[7:0];
            if (read_cycle || write_commit)
                transfer_pending <= 1'b0;

            if (!timing_done)
                delay_left <= delay_left - 1'b1;

            if (do_refresh || ((state == INIT_REF2) && timing_done))
                refresh_age <= {REFRESH_BITS{1'b0}};
            else if (initialized || (state == INIT_MODE) || (state == CLOSED))
                refresh_age <= refresh_age + 1'b1;

            if ((state == POWERUP) && (powerup_left != 0)) begin
                powerup_left <= powerup_left - 1'b1;
            end else if (req && accept) begin
                active_addr <= addr;
                active_we <= we;
                active_wdata <= wdata;
                transfer_pending <= 1'b1;
                state <= ACTIVATE;
            end else if (timing_done) begin
                case (state)
                    CKE_LOW: state <= POWERUP;
                    POWERUP: state <= INIT_PRE;
                    INIT_PRE: begin
                        state <= INIT_REF1;
                        delay_left <= RP_WAIT;
                    end
                    INIT_REF1: begin
                        state <= INIT_REF2;
                        delay_left <= RFC_WAIT;
                    end
                    INIT_REF2: begin
                        state <= INIT_MODE;
                        delay_left <= RFC_WAIT;
                    end
                    INIT_MODE: begin
                        state <= CLOSED;
                        delay_left <= MRD_WAIT;
                    end
                    CLOSED: begin
                        initialized <= 1'b1;
                        if (do_refresh)
                            delay_left <= RFC_WAIT;
                    end
                    ACTIVATE: begin
                        state <= ACCESS;
                        delay_left <= RCD_WAIT;
                    end
                    ACCESS: begin
                        state <= PRECHARGE;
                        delay_left <= active_we ? WRITE_WAIT : READ_WAIT;
                    end
                    PRECHARGE: begin
                        state <= CLOSED;
                        delay_left <= RP_WAIT;
                    end
                    default: state <= CKE_LOW;
                endcase
            end
        end
    end
endmodule
