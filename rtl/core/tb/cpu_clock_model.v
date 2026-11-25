`timescale 1ps/1ps

module cpu_clock_model #(
    parameter integer FABRIC_PERIOD_PS = 11640
) (
    output reg clk_cpu = 1'b0
);
    integer alignment;
    initial begin
        if (!$value$plusargs("cpu_align=%d", alignment))
            alignment = 0;
        #(FABRIC_PERIOD_PS / 2 + alignment * FABRIC_PERIOD_PS);
        forever begin
            clk_cpu = !clk_cpu;
            #(FABRIC_PERIOD_PS);
        end
    end
endmodule
