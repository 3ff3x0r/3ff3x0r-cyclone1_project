// The two clocks come from the same PLL. Every transfer is register to
// register and uses the normal related-clock setup and hold checks.
module cpu_clock_bridge (
    input  wire       clk_sys,
    input  wire       clk_cpu,
    input  wire       rst_n,
    input  wire       run,
    input  wire       ce_p,
    input  wire       ce_n,
    input  wire       int_n,
    input  wire [7:0] data_in,
    output wire       phase_ready,
    output wire       phase_pending,
    output reg [15:0] addr,
    output reg  [7:0] data_out,
    output reg        m1_n,
    output reg        mreq_n,
    output reg        iorq_n,
    output reg        rd_n,
    output reg        wr_n,
    output reg        rfsh_n,
    output reg        read_on_neg
);
    localparam [5:0] BUS_INACTIVE = 6'b111111;
    localparam [1:0] IDLE = 2'd0, EXECUTE = 2'd1, PUBLISH = 2'd2;

    reg request_id, accepted_id, published_id;
    reg request_reset, request_pos, request_int_n;
    reg [7:0] request_data;
    reg was_running, reset_owed;
    wire busy = request_id != accepted_id;
    wire reset_requested = reset_owed || (was_running && !run);
    assign phase_pending = busy || reset_requested;
    assign phase_ready = run && !phase_pending;

    reg [30:0] cpu_bus;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            request_id <= 1'b0;
            accepted_id <= 1'b0;
            request_reset <= 1'b0;
            request_pos <= 1'b0;
            request_int_n <= 1'b1;
            request_data <= 8'hff;
            was_running <= 1'b0;
            reset_owed <= 1'b0;
            {addr, data_out, m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, read_on_neg}
                <= {24'b0, BUS_INACTIVE, 1'b0};
        end else begin
            was_running <= run;
            if (reset_requested) begin
                // A warm reset can be shorter than a CPU clock. Queue it
                // behind the accepted phase and discard that phase's bus.
                reset_owed <= busy;
                if (!busy) begin
                    request_id <= !request_id;
                    request_reset <= 1'b1;
                end
            end else if (phase_ready && (ce_p || ce_n)) begin
                request_id <= !request_id;
                request_reset <= 1'b0;
                request_pos <= ce_p;
                request_int_n <= int_n;
                request_data <= data_in;
            end

            if (published_id != accepted_id)
                accepted_id <= published_id;
            if (!run || reset_requested)
                {addr, data_out, m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, read_on_neg}
                    <= {24'b0, BUS_INACTIVE, 1'b0};
            else if (published_id != accepted_id)
                {addr, data_out, m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, read_on_neg} <= cpu_bus;
        end
    end

    reg [1:0] stage;
    reg captured_id, pos_phase, cpu_int_n, cpu_reset_n;
    reg [7:0] cpu_data_in;
    wire cpu_ce_p = stage == EXECUTE && cpu_reset_n && pos_phase;
    wire cpu_ce_n = stage == EXECUTE && cpu_reset_n && !pos_phase;
    wire [15:0] cpu_addr;
    wire [7:0] cpu_data_out;
    wire cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n, cpu_read_on_neg;

    always @(posedge clk_cpu or negedge rst_n) begin
        if (!rst_n) begin
            stage <= IDLE;
            captured_id <= 1'b0;
            published_id <= 1'b0;
            pos_phase <= 1'b0;
            cpu_int_n <= 1'b1;
            cpu_reset_n <= 1'b0;
            cpu_data_in <= 8'hff;
            cpu_bus <= {24'b0, BUS_INACTIVE, 1'b0};
        end else begin
            case (stage)
                IDLE: if (request_id != published_id) begin
                    captured_id <= request_id;
                    pos_phase <= request_pos;
                    cpu_int_n <= request_int_n;
                    // A reset token holds T80 in reset until the ingress
                    // register takes the first phase after restart.
                    cpu_reset_n <= !request_reset;
                    cpu_data_in <= request_data;
                    stage <= EXECUTE;
                end
                EXECUTE: stage <= PUBLISH;
                PUBLISH: begin
                    cpu_bus <= {cpu_addr, cpu_data_out, cpu_m1_n, cpu_mreq_n,
                                cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n, cpu_read_on_neg};
                    published_id <= captured_id;
                    stage <= IDLE;
                end
                default: stage <= IDLE;
            endcase
        end
    end

    spectrum_cpu cpu (
        .clk_sys(clk_cpu), .reset_n(cpu_reset_n), .ce_p(cpu_ce_p), .ce_n(cpu_ce_n),
        .int_n(cpu_int_n), .m1_n(cpu_m1_n), .mreq_n(cpu_mreq_n),
        .iorq_n(cpu_iorq_n), .rd_n(cpu_rd_n), .wr_n(cpu_wr_n), .rfsh_n(cpu_rfsh_n),
        .addr(cpu_addr), .data_in(cpu_data_in), .data_out(cpu_data_out), .read_on_neg(cpu_read_on_neg)
    );
endmodule
