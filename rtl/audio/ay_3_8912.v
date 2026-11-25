//
// Copyright (c) MikeJ - Jan 2005
// Copyright (c) 2016-2018 Sorgelig
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

// AY-only adaptation of ym2149.sv from ZX_Spectrum-128K_MIST at 9713924.
module ay_3_8912 #(
    parameter [7:0] IO_A_INPUT = 8'hff
) (
    input  wire       clk_sys,
    input  wire       reset_n,
    input  wire       cfg_psg_enable,
    input  wire       ce_psg,
    input  wire       ay_req,
    input  wire [1:0] ay_op,
    input  wire [7:0] ay_wdata,
    output reg  [7:0] ay_rdata,
    output wire [7:0] psg_a,
    output wire [7:0] psg_b,
    output wire [7:0] psg_c
);
    function [7:0] register_mask;
        input integer index;
        begin
            case (index)
                1, 3, 5, 13: register_mask = 8'h0f;
                6, 8, 9, 10: register_mask = 8'h1f;
                default:     register_mask = 8'hff;
            endcase
        end
    endfunction

    // The donor table's 16 AY levels, highest to lowest. A packed constant
    // keeps the three amplitude lookups in combinational logic.
    localparam [127:0] AMPLITUDES = {
        8'hff, 8'hd7, 8'hb5, 8'h90, 8'h72, 8'h5b, 8'h41, 8'h28,
        8'h22, 8'h15, 8'h0f, 8'h0a, 8'h06, 8'h04, 8'h03, 8'h00
    };

    reg [3:0] selected;
    reg selected_valid;
    wire write_register = cfg_psg_enable && ay_req && ay_op == 2'd1 && selected_valid;
    wire write_shape = write_register && selected == 4'd13;
    wire [7:0] registers [0:15];
    always @(posedge clk_sys or negedge reset_n) begin
        if (!reset_n) begin
            selected <= 0;
            selected_valid <= 1'b1;
        end else if (cfg_psg_enable && ay_req && ay_op == 2'd0) begin
            selected <= ay_wdata[3:0];
            selected_valid <= ay_wdata[7:4] == 0;
        end
    end

    genvar index;
    generate
        for (index = 0; index < 16; index = index + 1) begin : register_file
            localparam [3:0] ADDRESS = index;
            reg [7:0] value;
            always @(posedge clk_sys or negedge reset_n) begin
                if (!reset_n)
                    value <= 0;
                else if (write_register && selected == ADDRESS)
                    value <= ay_wdata & register_mask(index);
            end
            assign registers[index] = value;
        end
    endgenerate

    // C can sample the selected byte before its end-of-cycle ay_req pulse.
    // R15 retains an internal latch but the AY-3-8912 has no Port B pads.
    wire [7:0] selected_value = registers[selected];
    wire [7:0] port_a_value = registers[7][6] ? registers[14] & IO_A_INPUT : IO_A_INPUT;
    wire [7:0] port_b_value = registers[7][7] ? registers[15] : 8'hff;
    always @* begin
        ay_rdata = 8'hff;
        if (reset_n && cfg_psg_enable && selected_valid) begin
            case (selected)
                4'd14: ay_rdata = port_a_value;
                4'd15: ay_rdata = port_b_value;
                default: ay_rdata = selected_value;
            endcase
        end
    end

    // ce_psg is already the AY input clock. Tone flips every 8*T clocks,
    // and noise advances every 16*N clocks. A zero tone/noise period acts as 1.
    wire psg_tick = cfg_psg_enable && ce_psg;
    reg [3:0] divider;
    wire tone_tick = psg_tick && (&divider[2:0]);
    wire noise_tick = psg_tick && (&divider);
    reg [4:0] noise_count;
    reg [16:0] noise;
    wire [4:0] noise_elapsed = noise_count + 5'd1;
    always @(posedge clk_sys or negedge reset_n) begin
        if (!reset_n) begin
            divider <= 0;
            noise_count <= 0;
            noise <= 17'd1;
        end else begin
            if (psg_tick)
                divider <= divider + 4'd1;
            if (noise_tick) begin
                if (noise_elapsed >= registers[6][4:0]) begin
                    noise_count <= 0;
                    noise <= {noise[0] ^ noise[3], noise[16:1]};
                end else
                    noise_count <= noise_elapsed;
            end
        end
    end

    // Sixteen AY levels. Each step lasts 16*E clocks (8 when E=0).
    // A shape write restarts both the ramp and its clock phase.
    reg [2:0] env_divider;
    reg [16:0] env_count;
    reg [3:0] env_step;
    reg env_attack, env_alternate, env_hold, env_stopped;
    wire [15:0] env_period = {registers[12], registers[11]};
    wire [16:0] env_elapsed = env_count + 17'd1;
    wire [3:0] env_level = env_step ^ {4{env_attack}};
    always @(posedge clk_sys or negedge reset_n) begin
        if (!reset_n) begin
            env_divider <= 0;
            env_count <= 0;
            env_step <= 0;
            env_attack <= 1'b0;
            env_alternate <= 1'b0;
            env_hold <= 1'b0;
            env_stopped <= 1'b1;
        end else if (write_shape) begin
            env_divider <= 0;
            env_count <= 0;
            env_step <= 4'd15;
            env_attack <= ay_wdata[2];
            env_alternate <= ay_wdata[3] ? ay_wdata[1] : ay_wdata[2];
            env_hold <= !ay_wdata[3] || ay_wdata[0];
            env_stopped <= 1'b0;
        end else if (psg_tick && !env_stopped) begin
            env_divider <= env_divider + 3'd1;
            if (&env_divider) begin
                if (env_elapsed >= {env_period, 1'b0}) begin
                    env_count <= 0;
                    if (env_step != 0)
                        env_step <= env_step - 4'd1;
                    else begin
                        if (env_alternate)
                            env_attack <= !env_attack;
                        if (env_hold)
                            env_stopped <= 1'b1;
                        else
                            env_step <= 4'd15;
                    end
                end else
                    env_count <= env_elapsed;
            end
        end
    end

    wire [7:0] samples [0:2];
    generate
        for (index = 0; index < 3; index = index + 1) begin : channels
            wire [11:0] period = {registers[2*index+1][3:0], registers[2*index]};
            wire [4:0] volume = registers[8+index][4:0];
            wire [3:0] level = volume[4] ? env_level : volume[3:0];
            reg [11:0] count;
            reg tone;
            reg [7:0] sample;
            wire [11:0] elapsed = count + 12'd1;
            wire gate = (registers[7][index] || tone) &&
                        (registers[7][index+3] || noise[0]);
            always @(posedge clk_sys or negedge reset_n) begin
                if (!reset_n) begin
                    count <= 0;
                    tone <= 1'b0;
                    sample <= 0;
                end else begin
                    if (tone_tick) begin
                        if (elapsed >= period) begin
                            count <= 0;
                            tone <= !tone;
                        end else
                            count <= elapsed;
                    end
                    if (psg_tick)
                        sample <= gate ? AMPLITUDES[{level, 3'b000} +: 8] : 8'd0;
                end
            end
            assign samples[index] = cfg_psg_enable ? sample : 8'd0;
        end
    endgenerate
    assign {psg_a, psg_b, psg_c} = {samples[0], samples[1], samples[2]};
endmodule
