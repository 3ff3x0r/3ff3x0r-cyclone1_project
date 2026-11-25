module ps2_receiver #(
    parameter integer FRAME_TIMEOUT_CYCLES = 21478,
    // Consecutive samples per transition. The default is about 186 ns at 85.909 MHz.
    parameter integer CLOCK_FILTER_CYCLES = 16
) (
    input  wire       clk_sys,
    input  wire       rst_n,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    output reg  [7:0] byte_data,
    output reg        byte_valid,
    output reg        frame_error
);
    function integer count_width;
        input integer maximum;
        integer remaining;
        begin
            count_width = 1;
            for (remaining = maximum >> 1; remaining > 0; remaining = remaining >> 1)
                count_width = count_width + 1;
        end
    endfunction

    localparam integer LAST_TICK = FRAME_TIMEOUT_CYCLES - 1;
    localparam integer TIMER_WIDTH = count_width(LAST_TICK);
    localparam [TIMER_WIDTH-1:0] TIMEOUT = LAST_TICK[TIMER_WIDTH-1:0];
    localparam integer FILTER_LAST_TICK = CLOCK_FILTER_CYCLES - 1;
    localparam integer FILTER_WIDTH = count_width(FILTER_LAST_TICK);
    localparam [FILTER_WIDTH-1:0] FILTER_LIMIT = FILTER_LAST_TICK[FILTER_WIDTH-1:0];

    reg [1:0] clock_sync, data_sync;
    reg filtered_clock;
    reg [FILTER_WIDTH-1:0] clock_stable_ticks;
    wire clock_differs = clock_sync[1] != filtered_clock;
    wire clock_changed = clock_differs && clock_stable_ticks == FILTER_LIMIT;
    wire falling_clock = clock_changed && filtered_clock;
    reg armed;
    reg [TIMER_WIDTH-1:0] quiet_ticks;
    reg [3:0] bit_index;
    reg [9:0] frame;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            clock_sync <= 2'b11;
            data_sync <= 2'b11;
            filtered_clock <= 1'b1;
            clock_stable_ticks <= 0;
        end else begin
            clock_sync <= {clock_sync[0], ps2_clk};
            data_sync <= {data_sync[0], ps2_data};
            if (clock_changed)
                filtered_clock <= clock_sync[1];
            if (!clock_differs || clock_changed)
                clock_stable_ticks <= 0;
            else
                clock_stable_ticks <= clock_stable_ticks + 1'b1;
        end
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            armed <= 1'b0;
            quiet_ticks <= 0;
            bit_index <= 0;
            frame <= 0;
            byte_data <= 0;
            byte_valid <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            byte_valid <= 1'b0;
            frame_error <= 1'b0;
            if (!armed) begin
                // Wait for a bus idle gap after reset or a stalled low line.
                if (!clock_sync[1] || !data_sync[1])
                    quiet_ticks <= 0;
                else if (quiet_ticks == TIMEOUT) begin
                    armed <= 1'b1;
                    quiet_ticks <= 0;
                end else
                    quiet_ticks <= quiet_ticks + 1'b1;
            end else if (falling_clock) begin
                quiet_ticks <= 0;
                if (bit_index == 4'd10) begin
                    bit_index <= 0;
                    // The first ten bits are start, eight LSB-first data bits, parity.
                    if (!frame[0] && (^frame[9:1]) && data_sync[1]) begin
                        byte_data <= frame[8:1];
                        byte_valid <= 1'b1;
                    end else
                        frame_error <= 1'b1;
                end else begin
                    frame <= {data_sync[1], frame[9:1]};
                    bit_index <= bit_index + 1'b1;
                end
            end else if (bit_index != 0) begin
                if (quiet_ticks == TIMEOUT) begin
                    armed <= clock_sync[1] && data_sync[1];
                    quiet_ticks <= 0;
                    bit_index <= 0;
                    frame_error <= 1'b1;
                end else
                    quiet_ticks <= quiet_ticks + 1'b1;
            end
        end
    end
endmodule
