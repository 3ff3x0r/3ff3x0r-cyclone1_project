module video_clock_enables #(
    parameter integer CLK_SYS_HZ = 85909080
) (
    input  wire       clk_sys,
    input  wire       rst_n,
    input  wire [2:0] cfg_timing_id,
    input  wire       cfg_psg_enable,
    output wire       ce_cpu,
    output wire       ce_ula,
    output wire       ce_psg,
    output wire       clocks_ready
);
    function integer counter_bits;
        input integer maximum;
        integer remaining;
        begin
            counter_bits = 1;
            for (remaining = maximum >> 1; remaining > 0; remaining = remaining >> 1)
                counter_bits = counter_bits + 1;
        end
    endfunction

    // Use the native base clocks. TK selects frame height with the same
    // 14.30244 MHz master crystal in both modes. Pentagon uses 14 MHz.
    localparam [31:0] ULA_48_HZ  = 7000000;
    localparam [31:0] ULA_128_HZ = 7093800;
    localparam [31:0] ULA_TK_HZ  = 7151220;
    localparam [31:0] WRAP_48   = CLK_SYS_HZ - ULA_48_HZ;
    localparam [31:0] WRAP_128  = CLK_SYS_HZ - ULA_128_HZ;
    localparam [31:0] WRAP_TK   = CLK_SYS_HZ - ULA_TK_HZ;
    localparam integer PHASE_BITS = counter_bits(CLK_SYS_HZ - 1);

    reg [PHASE_BITS-1:0] increment;
    reg [PHASE_BITS-1:0] wrap_at;
    reg [PHASE_BITS-1:0] phase;
    reg [2:0] active_timing;
    reg configured;
    reg [1:0] ula_divider;
    reg ula_tick;
    reg cpu_tick;
    reg psg_tick;

    wire [2:0] timing_id = (cfg_timing_id <= 3'd5) ? cfg_timing_id : 3'd0;
    wire [PHASE_BITS:0] wrapped_phase = {1'b0, phase} - {1'b0, wrap_at};
    wire wrap = !wrapped_phase[PHASE_BITS];

    assign clocks_ready = configured && (active_timing == timing_id);
    assign ce_ula = clocks_ready && ula_tick;
    assign ce_cpu = clocks_ready && cpu_tick;
    assign ce_psg = clocks_ready && cfg_psg_enable && psg_tick;

    always @* begin
        case (active_timing)
            3'd1, 3'd2: begin
                increment = ULA_128_HZ[PHASE_BITS-1:0];
                wrap_at = WRAP_128[PHASE_BITS-1:0];
            end
            3'd3, 3'd4: begin
                increment = ULA_TK_HZ[PHASE_BITS-1:0];
                wrap_at = WRAP_TK[PHASE_BITS-1:0];
            end
            default: begin
                increment = ULA_48_HZ[PHASE_BITS-1:0];
                wrap_at = WRAP_48[PHASE_BITS-1:0];
            end
        endcase
    end

    // Exact integer-Hz modulus with at most one clk_sys tick of edge jitter.
    // CLK_SYS_HZ must be at least twice the fastest ULA rate so strobes
    // are separated by a low cycle. Each new timing starts at phase zero.
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            configured <= 1'b0;
            active_timing <= 3'd0;
            phase <= {PHASE_BITS{1'b0}};
            ula_divider <= 2'd0;
            ula_tick <= 1'b0;
            cpu_tick <= 1'b0;
            psg_tick <= 1'b0;
        end else if (!clocks_ready) begin
            configured <= 1'b1;
            active_timing <= timing_id;
            phase <= {PHASE_BITS{1'b0}};
            ula_divider <= 2'd0;
            ula_tick <= 1'b0;
            cpu_tick <= 1'b0;
            psg_tick <= 1'b0;
        end else begin
            ula_tick <= wrap;
            cpu_tick <= wrap && ula_divider[0];
            psg_tick <= wrap && (&ula_divider);
            phase <= wrap ? wrapped_phase[PHASE_BITS-1:0] : phase + increment;
            if (wrap)
                ula_divider <= ula_divider + 2'd1;
        end
    end
endmodule
