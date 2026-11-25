module audio_subsystem (
    input  wire       clk_sys,
    input  wire       rst_n,
    input  wire       guest_reset_n,
    input  wire       cfg_psg_enable,
    input  wire       ce_psg,
    input  wire       ay_req,
    input  wire [1:0] ay_op,
    input  wire [7:0] ay_wdata,
    output wire [7:0] ay_rdata,
    input  wire       beeper_bit,
    input  wire       mic_bit,
    input  wire       mic_record,
    output wire       mic_out,
    input  wire       ear_idle_bit,
    input  wire       tap_ear_valid,
    input  wire       tap_ear_bit,
    output wire       ear_bit,
    output reg  [5:0] audio_l,
    output reg  [5:0] audio_r
);
    wire reset_n = rst_n && guest_reset_n;
    wire [7:0] psg_a, psg_b, psg_c;
    ay_3_8912 psg (
        .clk_sys(clk_sys), .reset_n(reset_n), .cfg_psg_enable(cfg_psg_enable),
        .ce_psg(ce_psg), .ay_req(ay_req), .ay_op(ay_op), .ay_wdata(ay_wdata),
        .ay_rdata(ay_rdata), .psg_a(psg_a), .psg_b(psg_b), .psg_c(psg_c)
    );

    assign ear_bit = tap_ear_valid ? tap_ear_bit : ear_idle_bit;
    assign mic_out = reset_n && mic_bit;

    // A/B left, C/B right. Each PSG pair sums to at most 510, giving
    // at most 31 after scaling. The beeper adds 32 for a maximum of 63.
    wire [8:0] ay_l = {1'b0, psg_a} + {1'b0, psg_b};
    wire [8:0] ay_r = {1'b0, psg_c} + {1'b0, psg_b};
    wire unused_ay_lsb = &{ay_l[3:0], ay_r[3:0]};
    always @(posedge clk_sys or negedge reset_n) begin
        if (!reset_n) begin
            audio_l <= 0;
            audio_r <= 0;
        end else begin
            audio_l <= mic_record ? {6{mic_bit}} : {beeper_bit, ay_l[8:4]};
            audio_r <= {beeper_bit, ay_r[8:4]};
        end
    end
endmodule
