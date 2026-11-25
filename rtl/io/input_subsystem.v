module input_subsystem #(
    parameter integer CLK_SYS_HZ = 85909080,
    parameter integer PS2_CLOCK_FILTER_CYCLES = 16
) (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire        ps2_clk,
    input  wire        ps2_data,
    input  wire [5:0]  joy1_n,
    input  wire [5:0]  joy2_n,
    output wire [39:0] key_matrix_n,
    output wire [5:0]  joy1,
    output wire [5:0]  joy2,
    output wire        soft_reset_key,
    output wire        recovery_key,
    output wire        tap_play_toggle,
    output wire        tap_rewind
);
    wire [7:0] byte_data;
    wire byte_valid, frame_error;

    ps2_receiver #(
        .FRAME_TIMEOUT_CYCLES((CLK_SYS_HZ + 3999) / 4000),
        .CLOCK_FILTER_CYCLES(PS2_CLOCK_FILTER_CYCLES)
    ) receiver (
        .clk_sys(clk_sys), .rst_n(rst_n), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .byte_data(byte_data), .byte_valid(byte_valid), .frame_error(frame_error)
    );

    spectrum_ps2_keyboard #(.PREFIX_TIMEOUT_CYCLES((CLK_SYS_HZ + 199) / 200)) keyboard (
        .clk_sys(clk_sys), .rst_n(rst_n), .byte_data(byte_data),
        .byte_valid(byte_valid), .frame_error(frame_error), .key_matrix_n(key_matrix_n),
        .soft_reset_key(soft_reset_key), .recovery_key(recovery_key),
        .tap_play_toggle(tap_play_toggle), .tap_rewind(tap_rewind)
    );

    // The board pulls each of the six switches high. Publish both ports in
    // up, down, left, right, A, B bit order; C applies the latched mapping.
    reg [11:0] joy_meta, joy_sync;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            joy_meta <= 12'hfff;
            joy_sync <= 12'hfff;
        end else begin
            joy_meta <= {joy2_n, joy1_n};
            joy_sync <= joy_meta;
        end
    end
    assign {joy2, joy1} = ~joy_sync;
endmodule
