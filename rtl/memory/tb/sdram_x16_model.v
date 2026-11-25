`timescale 1ps/1ps

// Behavioral model for the commands used by the controller. Timing minima
// come from the Micron -75 data sheet and are checked in time, independently
// of the controller's rounding and scheduling.
module sdram_x16_model #(
    parameter ROW_BITS = 13,
    parameter COL_BITS = 9,
    parameter BANK_BITS = 2,
    parameter POWERUP_PS = 100000000
) (
    input  wire        rst_n,
    input  wire        clk,
    input  wire        cke,
    input  wire        cs_n,
    input  wire        ras_n,
    input  wire        cas_n,
    input  wire        we_n,
    input  wire [12:0] a,
    input  wire [1:0]  ba,
    input  wire [1:0]  dqm,
    inout  wire [15:0] dq,
    output wire [24:0] column_word_addr
);
    localparam [3:0] PRE = 4'b0010, REF = 4'b0001, MODE = 4'b0000,
                     ACT = 4'b0011, RD = 4'b0101, WR = 4'b0100,
                     NOP = 4'b0111;
    localparam NUM_BANKS = 1 << BANK_BITS;
    localparam WORD_BITS = ROW_BITS + COL_BITS + BANK_BITS;
    localparam [3:0] NEED_PRE = 0, NEED_REF1 = 1, NEED_REF2 = 2,
                     NEED_MODE = 3, OPERATIONAL = 4;
    localparam TRCD_PS = 20000, TRP_PS = 20000, TRFC_PS = 66000,
               TRAS_PS = 44000, TRC_PS = 66000, TRRD_PS = 15000,
               TWR_EXTRA_PS = 7500, TAC_PS = 5400, TOH_PS = 1800,
               TREFI_PS = 7812500, CAS = 3, TMRD = 3;

    reg [15:0] storage [0:(1 << WORD_BITS)-1];
    reg [ROW_BITS-1:0] open_row [0:NUM_BANKS-1];
    reg [NUM_BANKS-1:0] open;
    time activated_at [0:NUM_BANKS-1];
    time precharged_at [0:NUM_BANKS-1];
    time read_at [0:NUM_BANKS-1];
    time written_at [0:NUM_BANKS-1];
    time last_ref_at;
    time last_act_at;
    time mode_at;
    time power_started_at;
    time previous_clk_at;
    time clock_period;
    reg [3:0] phase;
    reg cke_seen;
    integer mode_cycle;
    integer cycle;
    integer refresh_count;
    integer max_refresh_ps;
    integer bank;

    integer read_output_cycle;
    reg [15:0] read_word;
    reg [1:0] dqm_one_cycle_ago;
    reg [1:0] dqm_two_cycles_ago;
    reg [15:0] dq_data;
    reg [1:0] dq_drive;

    wire [3:0] command = {cs_n, ras_n, cas_n, we_n};
    wire [BANK_BITS-1:0] chip_bank = ba[BANK_BITS-1:0];
    wire [WORD_BITS-1:0] word_index = {open_row[chip_bank], chip_bank, a[COL_BITS-1:0]};
    assign column_word_addr = {{(25-WORD_BITS){1'b0}}, word_index};
    assign dq[7:0] = dq_drive[0] ? dq_data[7:0] : 8'bz;
    assign dq[15:8] = dq_drive[1] ? dq_data[15:8] : 8'bz;

    always @(posedge rst_n)
        power_started_at = $time;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase = NEED_PRE;
            open = 0;
            cke_seen = 0;
            cycle = 0;
            refresh_count = 0;
            max_refresh_ps = 0;
            last_ref_at = 0;
            last_act_at = 0;
            mode_at = 0;
            mode_cycle = -TMRD;
            previous_clk_at = 0;
            read_output_cycle = -1;
            dq_data <= 0;
            dq_drive <= 0;
            dqm_one_cycle_ago <= 2'b11;
            dqm_two_cycles_ago <= 2'b11;
            for (bank = 0; bank < NUM_BANKS; bank = bank + 1) begin
                activated_at[bank] = 0;
                precharged_at[bank] = 0;
                read_at[bank] = 0;
                written_at[bank] = 0;
            end
        end else begin
            cycle = cycle + 1;
            clock_period = $time - previous_clk_at;
            previous_clk_at = $time;

            if (last_ref_at != 0 && ($time - last_ref_at > TREFI_PS))
                $fatal(1, "Distributed refresh interval exceeded at %0t", $time);

            dqm_one_cycle_ago <= dqm;
            dqm_two_cycles_ago <= dqm_one_cycle_ago;
            if (cycle == read_output_cycle) begin
                dq_data <= #(TAC_PS) read_word;
                dq_drive <= #(TAC_PS) ~dqm_two_cycles_ago;
            end else begin
                dq_drive <= #(TOH_PS) 2'b00;
            end

            if (!cke && (!cs_n || cke_seen))
                $fatal(1, "Unexpected CKE low at %0t", $time);

            if (!cs_n && command != NOP) begin
                if (!cke_seen || $time - power_started_at < POWERUP_PS)
                    $fatal(1, "Command before power-up/CKE wait finished");
                if (last_ref_at != 0 && $time - last_ref_at < TRFC_PS)
                    $fatal(1, "tRFC violated at %0t", $time);
                if (cycle - mode_cycle < TMRD)
                    $fatal(1, "tMRD violated at %0t", $time);

                case (command)
                    PRE: begin
                        if (phase == NEED_PRE) begin
                            if (!a[10])
                                $fatal(1, "Initialization needs PRECHARGE ALL");
                            phase = NEED_REF1;
                        end else if (phase != OPERATIONAL) begin
                            $fatal(1, "Unexpected PRECHARGE during initialization");
                        end
                        for (bank = 0; bank < NUM_BANKS; bank = bank + 1) begin
                            if (a[10] || bank == int'(chip_bank)) begin
                                if (open[bank] && $time - activated_at[bank] < TRAS_PS)
                                    $fatal(1, "tRAS violated on bank %0d", bank);
                                if (read_at[bank] != 0 && $time - read_at[bank] < clock_period)
                                    $fatal(1, "PRECHARGE truncated a one-word READ");
                                if (written_at[bank] != 0 &&
                                    $time - written_at[bank] < clock_period + TWR_EXTRA_PS)
                                    $fatal(1, "tWR violated on bank %0d", bank);
                                open[bank] = 0;
                                precharged_at[bank] = $time;
                            end
                        end
                    end
                    REF: begin
                        if (open != 0)
                            $fatal(1, "AUTO REFRESH with open banks");
                        for (bank = 0; bank < NUM_BANKS; bank = bank + 1)
                            if ($time - precharged_at[bank] < TRP_PS)
                                $fatal(1, "tRP violated before AUTO REFRESH");
                        case (phase)
                            NEED_REF1: phase = NEED_REF2;
                            NEED_REF2: phase = NEED_MODE;
                            OPERATIONAL: refresh_count = refresh_count + 1;
                            default: $fatal(1, "AUTO REFRESH out of initialization order");
                        endcase
                        if (last_ref_at != 0 && $time - last_ref_at > max_refresh_ps)
                            max_refresh_ps = int'($time - last_ref_at);
                        last_ref_at = $time;
                    end
                    MODE: begin
                        if (phase != NEED_MODE || open != 0 || ba != 0 || a != 13'h230)
                            $fatal(1, "Expected BL1, sequential, CL3, single-write mode");
                        phase = OPERATIONAL;
                        mode_cycle = cycle;
                        mode_at = $time;
                    end
                    ACT: begin
                        if (phase != OPERATIONAL || open[chip_bank])
                            $fatal(1, "ACTIVATE before initialization or with bank open");
                        if (a >> ROW_BITS != 0 || ba >> BANK_BITS != 0)
                            $fatal(1, "ACTIVATE sets unused address pins");
                        if ($time - precharged_at[chip_bank] < TRP_PS)
                            $fatal(1, "tRP violated before ACTIVATE");
                        if (activated_at[chip_bank] != 0 && $time - activated_at[chip_bank] < TRC_PS)
                            $fatal(1, "tRC violated before ACTIVATE");
                        if (last_act_at != 0 && $time - last_act_at < TRRD_PS)
                            $fatal(1, "tRRD violated before ACTIVATE");
                        open[chip_bank] = 1;
                        open_row[chip_bank] = a[ROW_BITS-1:0];
                        activated_at[chip_bank] = $time;
                        last_act_at = $time;
                    end
                    RD, WR: begin
                        if (phase != OPERATIONAL || !open[chip_bank])
                            $fatal(1, "READ/WRITE without initialized active row");
                        if ($time - activated_at[chip_bank] < TRCD_PS)
                            $fatal(1, "tRCD violated before READ/WRITE");
                        if (a >> COL_BITS != 0 || ba >> BANK_BITS != 0)
                            $fatal(1, "Expected explicit precharge and zero unused column pins");

                        if (command == RD) begin
                            if (cycle <= read_output_cycle)
                                $fatal(1, "Model supports one burst in flight");
                            read_output_cycle = cycle + CAS;
                            read_word = storage[word_index];
                            read_at[chip_bank] = $time;
                        end else begin
                            if (dq_drive != 0)
                                $fatal(1, "WRITE conflicts with SDRAM read drive");
                            if (!dqm[0]) begin
                                if ((^dq[7:0]) === 1'bx)
                                    $fatal(1, "Invalid data on enabled WRITE low lane");
                                storage[word_index][7:0] = dq[7:0];
                            end
                            if (!dqm[1]) begin
                                if ((^dq[15:8]) === 1'bx)
                                    $fatal(1, "Invalid data on enabled WRITE high lane");
                                storage[word_index][15:8] = dq[15:8];
                            end
                            written_at[chip_bank] = $time;
                        end
                    end
                    default: $fatal(1, "Unsupported SDRAM command %b", command);
                endcase
            end
            if (cke)
                cke_seen = 1;
        end
    end
endmodule
