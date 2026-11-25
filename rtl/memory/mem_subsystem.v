module mem_subsystem #(
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
    output wire        mem_ready,
    output wire        mem_idle,

    input  wire        cpu_mem_req,
    output wire        cpu_mem_accept,
    input  wire [21:0] cpu_mem_addr,
    input  wire        cpu_mem_we,
    input  wire [7:0]  cpu_mem_wdata,
    output wire        cpu_mem_rvalid,
    output wire [7:0]  cpu_mem_rdata,

    input  wire        ld_mem_req,
    output wire        ld_mem_accept,
    input  wire [21:0] ld_mem_addr,
    input  wire        ld_mem_we,
    input  wire [7:0]  ld_mem_wdata,
    output wire        ld_mem_rvalid,
    output wire [7:0]  ld_mem_rdata,

    input  wire        screen_rd_req,
    input  wire        screen_rd_bank7,
    input  wire [12:0] screen_rd_offset,
    output wire        screen_rd_valid,
    output wire [7:0]  screen_rd_data,

    output wire        sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire [12:0] sdram_a,
    output wire [1:0]  sdram_ba,
    output wire [1:0]  sdram_dqm,
    inout  wire [15:0] sdram_dq
);
    wire        issue_req;
    wire        issue_accept;
    wire [21:0] issue_addr;
    wire        issue_we;
    wire [7:0]  issue_wdata;
    wire        issue_busy;
    wire        issue_rvalid;
    wire [7:0]  issue_rdata;
    wire        write_commit;
    wire [21:0] write_addr;
    wire [7:0]  write_data;

    mem_arbiter arbiter (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .mem_ready(mem_ready),
        .mem_idle(mem_idle),
        .cpu_mem_req(cpu_mem_req),
        .cpu_mem_accept(cpu_mem_accept),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_we(cpu_mem_we),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rvalid(cpu_mem_rvalid),
        .cpu_mem_rdata(cpu_mem_rdata),
        .ld_mem_req(ld_mem_req),
        .ld_mem_accept(ld_mem_accept),
        .ld_mem_addr(ld_mem_addr),
        .ld_mem_we(ld_mem_we),
        .ld_mem_wdata(ld_mem_wdata),
        .ld_mem_rvalid(ld_mem_rvalid),
        .ld_mem_rdata(ld_mem_rdata),
        .issue_req(issue_req),
        .issue_accept(issue_accept),
        .issue_addr(issue_addr),
        .issue_we(issue_we),
        .issue_wdata(issue_wdata),
        .issue_busy(issue_busy),
        .issue_rvalid(issue_rvalid),
        .issue_rdata(issue_rdata)
    );

    sdram_x16 #(
        .ROW_BITS(ROW_BITS),
        .COL_BITS(COL_BITS),
        .BANK_BITS(BANK_BITS),
        .CLK_PERIOD_PS(CLK_PERIOD_PS),
        .POWERUP_CYCLES(POWERUP_CYCLES),
        .T_RCD_PS(T_RCD_PS),
        .T_RP_PS(T_RP_PS),
        .T_RFC_PS(T_RFC_PS),
        .T_RAS_PS(T_RAS_PS),
        .T_RC_PS(T_RC_PS),
        .T_WR_EXTRA_PS(T_WR_EXTRA_PS),
        .REFRESH_INTERVAL_PS(REFRESH_INTERVAL_PS)
    ) controller (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .initialized(mem_ready),
        .req(issue_req),
        .accept(issue_accept),
        .addr(issue_addr),
        .we(issue_we),
        .wdata(issue_wdata),
        .rvalid(issue_rvalid),
        .rdata(issue_rdata),
        .user_busy(issue_busy),
        .write_commit(write_commit),
        .write_addr(write_addr),
        .write_data(write_data),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_a(sdram_a),
        .sdram_ba(sdram_ba),
        .sdram_dqm(sdram_dqm),
        .sdram_dq(sdram_dq)
    );

    screen_mirror mirror (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .write_commit(write_commit),
        .write_addr(write_addr),
        .write_data(write_data),
        .screen_rd_req(screen_rd_req),
        .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(screen_rd_offset),
        .screen_rd_valid(screen_rd_valid),
        .screen_rd_data(screen_rd_data)
    );
endmodule
