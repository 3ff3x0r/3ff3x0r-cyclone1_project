module video_subsystem #(
    parameter integer CLK_SYS_HZ = 85909080
) (
    input  wire       clk_sys,
    input  wire       rst_n,
    input  wire [2:0] cfg_timing_id,
    input  wire       cfg_psg_enable,
    output wire       clocks_ready,
    output wire       ce_cpu,
    output wire       ce_ula,
    output wire       ce_psg,
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
    output wire [5:0] vga_r,
    output wire [5:0] vga_g,
    output wire [5:0] vga_b,
    output wire       vga_hs_n,
    output wire       vga_vs_n,
    output wire       vga_blank
);
    video_clock_enables #(.CLK_SYS_HZ(CLK_SYS_HZ)) enables (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .cfg_timing_id(cfg_timing_id),
        .cfg_psg_enable(cfg_psg_enable),
        .ce_cpu(ce_cpu),
        .ce_ula(ce_ula),
        .ce_psg(ce_psg),
        .clocks_ready(clocks_ready)
    );

    video_scandoubler scan (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .ula_px_ce(ula_px_ce),
        .ula_color(ula_color),
        .ula_x(ula_x),
        .ula_y(ula_y),
        .ula_hs_n(ula_hs_n),
        .ula_vs_n(ula_vs_n),
        .ula_blank(ula_blank),
        .loader_diag_active(loader_diag_active),
        .loader_diag_code(loader_diag_code),
        .clk_vga(clk_vga),
        .rst_vga_n(rst_vga_n),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hs_n(vga_hs_n),
        .vga_vs_n(vga_vs_n),
        .vga_blank(vga_blank)
    );
endmodule
