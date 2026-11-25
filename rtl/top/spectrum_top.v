module spectrum_top #(
    parameter integer CLK_SYS_HZ = 85909080,
    parameter BOOT_ROM_FILE = "",
    parameter [14:0] ROM_SLOT_BYTES = 15'd16384
) (
    input  wire        clk_sys,
    input  wire        clk_cpu,
    input  wire        rst_n,
    input  wire        clk_vga,
    input  wire        rst_vga_n,

    // SDRAM physical bus
    output wire        sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire [12:0] sdram_a,
    output wire [1:0]  sdram_ba,
    output wire [1:0]  sdram_dqm,
    inout  wire [15:0] sdram_dq,

    // VGA scanout (in clk_vga domain)
    output wire [5:0]  vga_r,
    output wire [5:0]  vga_g,
    output wire [5:0]  vga_b,
    output wire        vga_hs_n,
    output wire        vga_vs_n,
    output wire        vga_blank,

    // Physical input and audio pads
    input  wire        ps2_clk,
    input  wire        ps2_data,
    input  wire [5:0]  joy1_n,
    input  wire [5:0]  joy2_n,
    output wire [5:0]  audio_l,
    output wire [5:0]  audio_r,

    // Physical SD SPI pads
    output wire        sd_cs_n,
    output wire        sd_sck,
    output wire        sd_mosi,
    input  wire        sd_miso,

    // Loader/boot configuration & commit interface (driven by Ticket E firmware / TB)
    input  wire [3:0]  pending_profile_id,
    input  wire [1:0]  pending_ram_size_id,
    input  wire [2:0]  pending_timing_id,
    input  wire [2:0]  pending_paging_id,
    input  wire [15:0] pending_rom_set_id,
    input  wire [3:0]  pending_rom_valid_mask,
    input  wire        pending_psg_enable,
    input  wire [1:0]  pending_disk_kind,
    input  wire [1:0]  pending_input_map_id,
    input  wire [1:0]  pending_joy1_b_map,
    input  wire [1:0]  pending_joy2_b_map,
    input  wire        boot_commit_valid,
    output wire        boot_commit_ready,
    input  wire        boot_stage_ok,
    input  wire        boot_ram_init_ok,
    output wire        boot_publish,
    output wire        boot_commit_done,
    output wire [7:0]  boot_error,
    output wire        boot_recovery,
    input  wire        loader_diag_active,
    input  wire [7:0]  loader_diag_code,

    // Optional external loader/media DMA port (active when promotion is idle)
    input  wire        ext_ld_mem_req,
    output wire        ext_ld_mem_accept,
    input  wire [21:0] ext_ld_mem_addr,
    input  wire        ext_ld_mem_we,
    input  wire [7:0]  ext_ld_mem_wdata,
    output wire        ext_ld_mem_rvalid,
    output wire [7:0]  ext_ld_mem_rdata,

    // Status outputs
    output wire        mem_ready,
    output wire        clocks_ready,
    output wire        boot_overlay,
    output wire        cfg_valid,
    output wire        cpu_mem_deadline_miss
);
    // Orchestrator & configuration wires
    wire        mem_idle;
    wire        cpu_quiesce;
    wire        cpu_quiesced;
    wire        media_quiesce;
    wire        sd_idle;
    wire        boot_sd_idle;
    wire        media_idle = sd_idle && boot_sd_idle;

    wire        sd_owner_boot;
    wire        cpu_reset_n;
    wire        guest_reset_n;
    wire [3:0]  cfg_profile_id;
    wire [1:0]  cfg_ram_size_id;
    wire [2:0]  cfg_timing_id;
    wire [2:0]  cfg_paging_id;
    wire [15:0] cfg_rom_set_id;
    wire [3:0]  cfg_rom_valid_mask;
    wire        cfg_psg_enable;
    wire [1:0]  cfg_disk_kind;
    wire [1:0]  cfg_input_map_id;
    wire [1:0]  cfg_joy1_b_map;
    wire [1:0]  cfg_joy2_b_map;

    // ROM promotion DMA wires
    wire        promo_active;
    wire        promo_mem_req;
    wire        promo_mem_accept;
    wire [21:0] promo_mem_addr;
    wire        promo_mem_we;
    wire [7:0]  promo_mem_wdata;
    wire        promo_mem_rvalid;
    wire [7:0]  promo_mem_rdata;

    // Memory client muxing: CPU guest vs boot_bus_adapter
    wire        core_mem_req, core_mem_accept, core_mem_we, core_mem_rvalid;
    wire [21:0] core_mem_addr;
    wire [7:0]  core_mem_wdata, core_mem_rdata;

    wire        boot_mem_req, boot_mem_accept, boot_mem_we, boot_mem_rvalid;
    wire [21:0] boot_mem_addr;
    wire [7:0]  boot_mem_wdata, boot_mem_rdata;

    wire        mem_cpu_req    = boot_overlay ? boot_mem_req   : core_mem_req;
    wire [21:0] mem_cpu_addr   = boot_overlay ? boot_mem_addr  : core_mem_addr;
    wire        mem_cpu_we     = boot_overlay ? boot_mem_we    : core_mem_we;
    wire [7:0]  mem_cpu_wdata  = boot_overlay ? boot_mem_wdata : core_mem_wdata;
    wire        mem_cpu_accept;
    wire        mem_cpu_rvalid;
    wire [7:0]  mem_cpu_rdata;

    assign boot_mem_accept = boot_overlay ? mem_cpu_accept : 1'b0;
    assign core_mem_accept = !boot_overlay ? mem_cpu_accept : 1'b0;
    assign boot_mem_rvalid = boot_overlay ? mem_cpu_rvalid : 1'b0;
    assign core_mem_rvalid = !boot_overlay ? mem_cpu_rvalid : 1'b0;
    assign boot_mem_rdata  = mem_cpu_rdata;
    assign core_mem_rdata  = mem_cpu_rdata;

    // Loader port muxing: ROM promotion vs external loader/media
    wire        ld_mem_req    = promo_active ? promo_mem_req   : ext_ld_mem_req;
    wire [21:0] ld_mem_addr   = promo_active ? promo_mem_addr  : ext_ld_mem_addr;
    wire        ld_mem_we     = promo_active ? promo_mem_we    : ext_ld_mem_we;
    wire [7:0]  ld_mem_wdata  = promo_active ? promo_mem_wdata : ext_ld_mem_wdata;
    wire        ld_mem_accept;
    wire        ld_mem_rvalid;
    wire [7:0]  ld_mem_rdata;

    assign promo_mem_accept  = promo_active ? ld_mem_accept : 1'b0;
    assign ext_ld_mem_accept = !promo_active ? ld_mem_accept : 1'b0;
    assign promo_mem_rvalid  = promo_active ? ld_mem_rvalid : 1'b0;
    assign ext_ld_mem_rvalid = !promo_active ? ld_mem_rvalid : 1'b0;
    assign promo_mem_rdata   = ld_mem_rdata;
    assign ext_ld_mem_rdata  = ld_mem_rdata;

    // Boot CPU bus & SD bridge wires
    wire        boot_bus_req, boot_bus_io, boot_bus_we, boot_bus_ready;
    wire [15:0] boot_bus_addr;
    wire [7:0]  boot_bus_wdata, boot_bus_rdata;
    wire        sd_bridge_ready;
    wire [7:0]  sd_bridge_rdata;

    wire        sd_blk_req, sd_blk_ready, sd_blk_we;
    wire [31:0] sd_blk_lba;
    wire        sd_blk_tx_valid, sd_blk_tx_ready;
    wire [7:0]  sd_blk_tx_data;
    wire        sd_blk_rx_valid, sd_blk_rx_ready;
    wire [7:0]  sd_blk_rx_data;
    wire        sd_blk_done;
    wire [3:0]  sd_blk_error;

    // Video, input, audio wires
    wire        ce_cpu, ce_ula, ce_psg, psg_ce;
    wire        screen_rd_req, screen_rd_bank7, screen_rd_valid;
    wire [12:0] screen_rd_offset;
    wire [7:0]  screen_rd_data;
    wire        ula_px_ce, ula_hs_n, ula_vs_n, ula_blank;
    wire [3:0]  ula_color;
    wire [9:0]  ula_x;
    wire [8:0]  ula_y;

    wire [39:0] key_matrix_n;
    wire [5:0]  joy1, joy2;
    wire        soft_reset_key, recovery_key, tap_play_toggle, tap_rewind;
    wire        ear_bit, mic_bit, beeper_bit, mic_out;
    wire        ay_req;
    wire [1:0]  ay_op;
    wire [7:0]  ay_wdata, ay_rdata;

    wire        disk_req, disk_we, disk_motor;
    wire [2:0]  disk_reg;
    wire [7:0]  disk_wdata;

    // Tie off unused future Ticket G / profile metadata wires cleanly
    wire unused_signals = &{
        1'b0, cfg_profile_id, cfg_ram_size_id, cfg_rom_set_id,
        tap_play_toggle, tap_rewind, mic_out,
        disk_req, disk_we, disk_reg, disk_wdata, disk_motor,
        sd_blk_tx_ready
    };

    boot_orchestrator #(
        .ROM_SLOT_BYTES(ROM_SLOT_BYTES)
    ) orchestrator (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .clocks_ready(clocks_ready), .mem_ready(mem_ready), .mem_idle(mem_idle),
        .cpu_quiesced(cpu_quiesced), .media_idle(media_idle),
        .soft_reset_key(soft_reset_key), .recovery_key(recovery_key),
        .pending_profile_id(pending_profile_id), .pending_ram_size_id(pending_ram_size_id),
        .pending_timing_id(pending_timing_id), .pending_paging_id(pending_paging_id),
        .pending_rom_set_id(pending_rom_set_id), .pending_rom_valid_mask(pending_rom_valid_mask),
        .pending_psg_enable(pending_psg_enable), .pending_disk_kind(pending_disk_kind),
        .pending_input_map_id(pending_input_map_id), .pending_joy1_b_map(pending_joy1_b_map),
        .pending_joy2_b_map(pending_joy2_b_map),
        .boot_commit_valid(boot_commit_valid), .boot_commit_ready(boot_commit_ready),
        .boot_stage_ok(boot_stage_ok), .boot_ram_init_ok(boot_ram_init_ok),
        .boot_publish(boot_publish), .boot_commit_done(boot_commit_done),
        .boot_error(boot_error), .boot_recovery(boot_recovery),
        .cfg_valid(cfg_valid), .cfg_profile_id(cfg_profile_id),
        .cfg_ram_size_id(cfg_ram_size_id), .cfg_timing_id(cfg_timing_id),
        .cfg_paging_id(cfg_paging_id), .cfg_rom_set_id(cfg_rom_set_id),
        .cfg_rom_valid_mask(cfg_rom_valid_mask), .cfg_psg_enable(cfg_psg_enable),
        .cfg_disk_kind(cfg_disk_kind), .cfg_input_map_id(cfg_input_map_id),
        .cfg_joy1_b_map(cfg_joy1_b_map), .cfg_joy2_b_map(cfg_joy2_b_map),
        .boot_overlay(boot_overlay), .sd_owner_boot(sd_owner_boot),
        .cpu_reset_n(cpu_reset_n), .guest_reset_n(guest_reset_n),
        .cpu_quiesce(cpu_quiesce), .media_quiesce(media_quiesce),
        .promo_active(promo_active), .promo_mem_req(promo_mem_req),
        .promo_mem_accept(promo_mem_accept), .promo_mem_addr(promo_mem_addr),
        .promo_mem_we(promo_mem_we), .promo_mem_wdata(promo_mem_wdata),
        .promo_mem_rvalid(promo_mem_rvalid), .promo_mem_rdata(promo_mem_rdata)
    );

    boot_bus_adapter #(
        .BOOT_ROM_FILE(BOOT_ROM_FILE)
    ) boot_adapter (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .boot_overlay(boot_overlay), .mem_ready(mem_ready),
        .boot_bus_req(boot_bus_req), .boot_bus_io(boot_bus_io),
        .boot_bus_we(boot_bus_we), .boot_bus_addr(boot_bus_addr),
        .boot_bus_wdata(boot_bus_wdata),
        .boot_bus_ready(boot_bus_ready), .boot_bus_rdata(boot_bus_rdata),
        .sd_bridge_ready(sd_bridge_ready), .sd_bridge_rdata(sd_bridge_rdata),
        .boot_mem_req(boot_mem_req), .boot_mem_accept(boot_mem_accept),
        .boot_mem_addr(boot_mem_addr), .boot_mem_we(boot_mem_we),
        .boot_mem_wdata(boot_mem_wdata),
        .boot_mem_rvalid(boot_mem_rvalid), .boot_mem_rdata(boot_mem_rdata)
    );

    mem_subsystem memory (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .mem_ready(mem_ready), .mem_idle(mem_idle),
        .cpu_mem_req(mem_cpu_req), .cpu_mem_accept(mem_cpu_accept),
        .cpu_mem_addr(mem_cpu_addr), .cpu_mem_we(mem_cpu_we),
        .cpu_mem_wdata(mem_cpu_wdata),
        .cpu_mem_rvalid(mem_cpu_rvalid), .cpu_mem_rdata(mem_cpu_rdata),
        .ld_mem_req(ld_mem_req), .ld_mem_accept(ld_mem_accept),
        .ld_mem_addr(ld_mem_addr), .ld_mem_we(ld_mem_we),
        .ld_mem_wdata(ld_mem_wdata),
        .ld_mem_rvalid(ld_mem_rvalid), .ld_mem_rdata(ld_mem_rdata),
        .screen_rd_req(screen_rd_req), .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(screen_rd_offset),
        .screen_rd_valid(screen_rd_valid), .screen_rd_data(screen_rd_data),
        .sdram_cke(sdram_cke), .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n), .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n), .sdram_a(sdram_a), .sdram_ba(sdram_ba),
        .sdram_dqm(sdram_dqm), .sdram_dq(sdram_dq)
    );

    core_subsystem core (
        .clk_sys(clk_sys), .clk_cpu(clk_cpu), .rst_n(rst_n),
        .cpu_reset_n(cpu_reset_n), .guest_reset_n(guest_reset_n),
        .cpu_quiesce(cpu_quiesce), .cpu_quiesced(cpu_quiesced),
        .boot_overlay(boot_overlay), .cfg_valid(cfg_valid),
        .cfg_timing_id(cfg_timing_id), .cfg_paging_id(cfg_paging_id),
        .cfg_rom_valid_mask(cfg_rom_valid_mask), .cfg_psg_enable(cfg_psg_enable),
        .cfg_disk_kind(cfg_disk_kind), .cfg_input_map_id(cfg_input_map_id),
        .cfg_joy1_b_map(cfg_joy1_b_map), .cfg_joy2_b_map(cfg_joy2_b_map),
        .ce_cpu(ce_cpu), .ce_ula(ce_ula), .ce_psg(ce_psg), .psg_ce(psg_ce),
        .mem_ready(mem_ready),
        .cpu_mem_req(core_mem_req), .cpu_mem_accept(core_mem_accept),
        .cpu_mem_addr(core_mem_addr), .cpu_mem_we(core_mem_we),
        .cpu_mem_wdata(core_mem_wdata),
        .cpu_mem_rvalid(core_mem_rvalid), .cpu_mem_rdata(core_mem_rdata),
        .cpu_mem_deadline_miss(cpu_mem_deadline_miss),
        .boot_bus_req(boot_bus_req), .boot_bus_io(boot_bus_io),
        .boot_bus_we(boot_bus_we), .boot_bus_addr(boot_bus_addr),
        .boot_bus_wdata(boot_bus_wdata),
        .boot_bus_ready(boot_bus_ready), .boot_bus_rdata(boot_bus_rdata),
        .screen_rd_req(screen_rd_req), .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(screen_rd_offset),
        .screen_rd_valid(screen_rd_valid), .screen_rd_data(screen_rd_data),
        .ula_px_ce(ula_px_ce), .ula_color(ula_color),
        .ula_x(ula_x), .ula_y(ula_y),
        .ula_hs_n(ula_hs_n), .ula_vs_n(ula_vs_n), .ula_blank(ula_blank),
        .key_matrix_n(key_matrix_n), .joy1(joy1), .joy2(joy2),
        .ear_bit(ear_bit), .mic_bit(mic_bit), .beeper_bit(beeper_bit),
        .ay_req(ay_req), .ay_op(ay_op), .ay_wdata(ay_wdata), .ay_rdata(ay_rdata),
        .disk_req(disk_req), .disk_we(disk_we), .disk_reg(disk_reg),
        .disk_wdata(disk_wdata), .disk_rdata(8'hff), .disk_motor(disk_motor)
    );

    video_subsystem #(.CLK_SYS_HZ(CLK_SYS_HZ)) video (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .cfg_timing_id(cfg_timing_id), .cfg_psg_enable(cfg_psg_enable),
        .clocks_ready(clocks_ready),
        .ce_cpu(ce_cpu), .ce_ula(ce_ula), .ce_psg(ce_psg),
        .ula_px_ce(ula_px_ce), .ula_color(ula_color),
        .ula_x(ula_x), .ula_y(ula_y),
        .ula_hs_n(ula_hs_n), .ula_vs_n(ula_vs_n), .ula_blank(ula_blank),
        .loader_diag_active(loader_diag_active), .loader_diag_code(loader_diag_code),
        .clk_vga(clk_vga), .rst_vga_n(rst_vga_n),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs_n(vga_hs_n), .vga_vs_n(vga_vs_n), .vga_blank(vga_blank)
    );

    input_subsystem #(.CLK_SYS_HZ(CLK_SYS_HZ)) input_io (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .joy1_n(joy1_n), .joy2_n(joy2_n),
        .key_matrix_n(key_matrix_n), .joy1(joy1), .joy2(joy2),
        .soft_reset_key(soft_reset_key), .recovery_key(recovery_key),
        .tap_play_toggle(tap_play_toggle), .tap_rewind(tap_rewind)
    );

    audio_subsystem audio (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .guest_reset_n(guest_reset_n), .cfg_psg_enable(cfg_psg_enable),
        .ce_psg(psg_ce), .ay_req(ay_req), .ay_op(ay_op),
        .ay_wdata(ay_wdata), .ay_rdata(ay_rdata),
        .beeper_bit(beeper_bit), .mic_bit(mic_bit),
        .mic_record(1'b0), .mic_out(mic_out),
        .ear_idle_bit(1'b1), .tap_ear_valid(1'b0), .tap_ear_bit(1'b0),
        .ear_bit(ear_bit), .audio_l(audio_l), .audio_r(audio_r)
    );

    boot_sd_bridge sd_bridge (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .sd_owner_boot(sd_owner_boot), .media_quiesce(media_quiesce),
        .boot_sd_idle(boot_sd_idle),
        .boot_bus_req(boot_bus_req), .boot_bus_io(boot_bus_io),
        .boot_bus_we(boot_bus_we), .boot_bus_addr(boot_bus_addr),
        .boot_bus_wdata(boot_bus_wdata),
        .boot_bus_ready(sd_bridge_ready), .boot_bus_rdata(sd_bridge_rdata),
        .sd_blk_req(sd_blk_req), .sd_blk_ready(sd_blk_ready),
        .sd_blk_lba(sd_blk_lba), .sd_blk_we(sd_blk_we),
        .sd_blk_tx_valid(sd_blk_tx_valid), .sd_blk_tx_data(sd_blk_tx_data),
        .sd_blk_rx_valid(sd_blk_rx_valid), .sd_blk_rx_data(sd_blk_rx_data),
        .sd_blk_rx_ready(sd_blk_rx_ready),
        .sd_blk_done(sd_blk_done), .sd_blk_error(sd_blk_error)
    );

    sd_spi_reader sd_reader (
        .clk_sys(clk_sys), .rst_n(rst_n),
        .sd_blk_req(sd_blk_req), .sd_blk_ready(sd_blk_ready),
        .sd_blk_lba(sd_blk_lba), .sd_blk_we(sd_blk_we),
        .sd_blk_tx_valid(sd_blk_tx_valid), .sd_blk_tx_data(sd_blk_tx_data),
        .sd_blk_tx_ready(sd_blk_tx_ready),
        .sd_blk_rx_valid(sd_blk_rx_valid), .sd_blk_rx_data(sd_blk_rx_data),
        .sd_blk_rx_ready(sd_blk_rx_ready),
        .sd_blk_done(sd_blk_done), .sd_blk_error(sd_blk_error),
        .media_quiesce(media_quiesce), .sd_idle(sd_idle),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
    );
endmodule
