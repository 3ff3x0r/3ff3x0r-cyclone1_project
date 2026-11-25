module boot_orchestrator #(
    parameter [14:0] ROM_SLOT_BYTES = 15'd16384
) (
    input  wire        clk_sys,
    input  wire        rst_n,

    // System readiness and drain status
    input  wire        clocks_ready,
    input  wire        mem_ready,
    input  wire        mem_idle,
    input  wire        cpu_quiesced,
    input  wire        media_idle,

    // Host keys from Ticket F (held levels in clk_sys)
    input  wire        soft_reset_key,
    input  wire        recovery_key,

    // Pending machine configuration from loader (E)
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

    // Boot commit handshake (E <-> A)
    input  wire        boot_commit_valid,
    output wire        boot_commit_ready,
    input  wire        boot_stage_ok,
    input  wire        boot_ram_init_ok,
    output wire        boot_publish,
    output reg         boot_commit_done,
    output reg  [7:0]  boot_error,
    output reg         boot_recovery,

    // Latched active configuration (A -> C/D/F/G)
    output reg         cfg_valid,
    output reg  [3:0]  cfg_profile_id,
    output reg  [1:0]  cfg_ram_size_id,
    output reg  [2:0]  cfg_timing_id,
    output reg  [2:0]  cfg_paging_id,
    output reg  [15:0] cfg_rom_set_id,
    output reg  [3:0]  cfg_rom_valid_mask,
    output reg         cfg_psg_enable,
    output reg  [1:0]  cfg_disk_kind,
    output reg  [1:0]  cfg_input_map_id,
    output reg  [1:0]  cfg_joy1_b_map,
    output reg  [1:0]  cfg_joy2_b_map,

    // Ownership, quiesce, and reset controls
    output reg         boot_overlay,
    output reg         sd_owner_boot,
    output reg         cpu_reset_n,
    output reg         guest_reset_n,
    output reg         cpu_quiesce,
    output reg         media_quiesce,

    // Exclusive loader-port DMA master for ROM staging -> active promotion
    output wire        promo_active,
    output wire        promo_mem_req,
    input  wire        promo_mem_accept,
    output wire [21:0] promo_mem_addr,
    output wire        promo_mem_we,
    output wire [7:0]  promo_mem_wdata,
    input  wire        promo_mem_rvalid,
    input  wire [7:0]  promo_mem_rdata
);
    localparam [2:0] BOOT_TIMING_ID = 3'd4; // TK90X PAL-M (60 Hz)

    localparam [3:0]
        ST_BOOT_WAIT     = 4'd0,
        ST_BOOT_RUN      = 4'd1,
        ST_COMMIT_QUIESCE = 4'd2,
        ST_PROMO_CHECK   = 4'd3,
        ST_PROMO_RD_REQ  = 4'd4,
        ST_PROMO_RD_WAIT = 4'd5,
        ST_PROMO_WR_REQ  = 4'd6,
        ST_PROMO_DRAIN   = 4'd7,
        ST_GUEST_RELEASE = 4'd8,
        ST_GUEST_RUN     = 4'd9,
        ST_SOFT_QUIESCE  = 4'd10,
        ST_RET_QUIESCE   = 4'd11;

    localparam [7:0]
        ERR_OK           = 8'd0,
        ERR_ROM_INVALID  = 8'd2,
        ERR_PROFILE      = 8'd3,
        ERR_MEM_CLOCK    = 8'd4,
        ERR_PROMO_FAIL   = 8'd5;

    reg [3:0]  state;
    reg        commit_armed;
    reg        prev_soft_key;
    reg        prev_rec_key;
    reg [1:0]  promo_slot;
    reg [14:0] promo_offset;
    reg [7:0]  promo_byte;

    // Validate pending profile combination per interfaces.md section 1.
    reg profile_ok;
    always @* begin
        profile_ok = 1'b0;
        case (pending_profile_id)
            4'd1: // Sinclair 16K
                profile_ok = (pending_ram_size_id == 2'd0) &&
                             (pending_paging_id == 3'd0) &&
                             (pending_timing_id == 3'd0) &&
                             (pending_rom_valid_mask == 4'b0001) &&
                             (pending_disk_kind == 2'd0);
            4'd2: // Sinclair 48K PAL
                profile_ok = (pending_ram_size_id == 2'd1) &&
                             (pending_paging_id == 3'd1) &&
                             (pending_timing_id == 3'd0) &&
                             (pending_rom_valid_mask == 4'b0001) &&
                             (pending_disk_kind == 2'd0);
            4'd3, 4'd4: // Sinclair 128K / grey +2
                profile_ok = (pending_ram_size_id == 2'd2) &&
                             (pending_paging_id == 3'd2) &&
                             (pending_timing_id == 3'd1) &&
                             (pending_rom_valid_mask == 4'b0011) &&
                             (pending_disk_kind == 2'd0);
            4'd5: // +2A
                profile_ok = (pending_ram_size_id == 2'd2) &&
                             (pending_paging_id == 3'd3) &&
                             (pending_timing_id == 3'd2) &&
                             (pending_rom_valid_mask == 4'b1111) &&
                             (pending_disk_kind == 2'd0);
            4'd6: // +3
                profile_ok = (pending_ram_size_id == 2'd2) &&
                             (pending_paging_id == 3'd3) &&
                             (pending_timing_id == 3'd2) &&
                             (pending_rom_valid_mask == 4'b1111) &&
                             (pending_disk_kind == 2'd0 || pending_disk_kind == 2'd1);
            4'd7: // TK90X
                profile_ok = ((pending_ram_size_id == 2'd0 && pending_paging_id == 3'd0) ||
                              (pending_ram_size_id == 2'd1 && pending_paging_id == 3'd1)) &&
                             (pending_timing_id == 3'd3 || pending_timing_id == 3'd4) &&
                             (pending_rom_valid_mask == 4'b0001) &&
                             (pending_disk_kind == 2'd0);
            4'd8: // Pentagon 128
                profile_ok = (pending_ram_size_id == 2'd2) &&
                             (pending_paging_id == 3'd4) &&
                             (pending_timing_id == 3'd5) &&
                             (pending_rom_valid_mask[1:0] == 2'b11) &&
                             (pending_rom_valid_mask[3] == 1'b0) &&
                             ((pending_disk_kind == 2'd0) ||
                              (pending_disk_kind == 2'd2 && pending_rom_valid_mask[2]));
            default:
                profile_ok = 1'b0;
        endcase

        if (pending_input_map_id == 2'd3)
            profile_ok = 1'b0;
        if (pending_joy2_b_map == 2'd3)
            profile_ok = 1'b0;
        if (pending_joy1_b_map == 2'd3 && pending_input_map_id != 2'd1)
            profile_ok = 1'b0;
    end

    wire soft_edge = soft_reset_key && !prev_soft_key;
    wire rec_edge  = recovery_key && !prev_rec_key;

    assign boot_commit_ready = (state == ST_BOOT_RUN) && commit_armed;
    assign promo_active = (state == ST_PROMO_CHECK) ||
                          (state == ST_PROMO_RD_REQ) ||
                          (state == ST_PROMO_RD_WAIT) ||
                          (state == ST_PROMO_WR_REQ) ||
                          (state == ST_PROMO_DRAIN);
    assign promo_mem_req = (state == ST_PROMO_RD_REQ) || (state == ST_PROMO_WR_REQ);
    assign promo_mem_we  = (state == ST_PROMO_WR_REQ);
    assign promo_mem_addr = (state == ST_PROMO_WR_REQ)
        ? {6'h02, promo_slot, promo_offset[13:0]}  // 020000 + (slot << 14)
        : {6'h03, promo_slot, promo_offset[13:0]}; // 030000 + (slot << 14)
    assign promo_mem_wdata = promo_byte;

    // The loader samples this enable on the edge that latches cfg_*.
    assign boot_publish = rst_n && (state == ST_PROMO_DRAIN) && clocks_ready && mem_ready && mem_idle;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_BOOT_WAIT;
            commit_armed       <= 1'b1;
            prev_soft_key      <= 1'b0;
            prev_rec_key       <= 1'b0;
            promo_slot         <= 2'd0;
            promo_offset       <= 15'd0;
            promo_byte         <= 8'd0;
            boot_commit_done   <= 1'b0;
            boot_error         <= ERR_OK;
            boot_recovery      <= 1'b0;
            cfg_valid          <= 1'b0;
            cfg_profile_id     <= 4'd0;
            cfg_ram_size_id    <= 2'd0;
            cfg_timing_id      <= BOOT_TIMING_ID;
            cfg_paging_id      <= 3'd0;
            cfg_rom_set_id     <= 16'd0;
            cfg_rom_valid_mask <= 4'd0;
            cfg_psg_enable     <= 1'b0;
            cfg_disk_kind      <= 2'd0;
            cfg_input_map_id   <= 2'd0;
            cfg_joy1_b_map     <= 2'd0;
            cfg_joy2_b_map     <= 2'd0;
            boot_overlay       <= 1'b1;
            sd_owner_boot      <= 1'b1;
            cpu_reset_n        <= 1'b0;
            guest_reset_n      <= 1'b0;
            cpu_quiesce        <= 1'b0;
            media_quiesce      <= 1'b0;
        end else begin
            boot_commit_done <= 1'b0;
            prev_soft_key    <= soft_reset_key;
            prev_rec_key     <= recovery_key;

            if (!boot_commit_valid)
                commit_armed <= 1'b1;

            case (state)
                ST_BOOT_WAIT: begin
                    boot_overlay  <= 1'b1;
                    sd_owner_boot <= 1'b1;
                    guest_reset_n <= 1'b0;
                    cpu_quiesce   <= 1'b0;
                    media_quiesce <= 1'b0;
                    if (recovery_key)
                        boot_recovery <= 1'b1;
                    if (clocks_ready) begin
                        cpu_reset_n <= 1'b1;
                        state       <= ST_BOOT_RUN;
                    end else begin
                        cpu_reset_n <= 1'b0;
                    end
                end

                ST_BOOT_RUN: begin
                    if (recovery_key)
                        boot_recovery <= 1'b1;
                    if (boot_commit_valid && commit_armed) begin
                        commit_armed <= 1'b0;
                        if (!clocks_ready || !mem_ready) begin
                            boot_error       <= ERR_MEM_CLOCK;
                            boot_commit_done <= 1'b1;
                        end else if (!boot_stage_ok || !boot_ram_init_ok) begin
                            boot_error       <= ERR_ROM_INVALID;
                            boot_commit_done <= 1'b1;
                        end else if (!profile_ok) begin
                            boot_error       <= ERR_PROFILE;
                            boot_commit_done <= 1'b1;
                        end else begin
                            cpu_quiesce   <= 1'b1;
                            media_quiesce <= 1'b1;
                            state         <= ST_COMMIT_QUIESCE;
                        end
                    end
                end

                ST_COMMIT_QUIESCE: begin
                    if (!clocks_ready || !mem_ready) begin
                        cpu_quiesce      <= 1'b0;
                        media_quiesce    <= 1'b0;
                        boot_error       <= ERR_MEM_CLOCK;
                        boot_commit_done <= 1'b1;
                        state            <= ST_BOOT_RUN;
                    end else if (cpu_quiesced && media_idle && mem_idle) begin
                        cpu_reset_n   <= 1'b0;
                        guest_reset_n <= 1'b0;
                        cfg_valid     <= 1'b0;
                        promo_slot    <= 2'd0;
                        promo_offset  <= 15'd0;
                        state         <= ST_PROMO_CHECK;
                    end
                end

                ST_PROMO_CHECK: begin
                    if (!clocks_ready || !mem_ready) begin
                        cpu_quiesce      <= 1'b0;
                        media_quiesce    <= 1'b0;
                        boot_error       <= ERR_PROMO_FAIL;
                        boot_commit_done <= 1'b1;
                        state            <= ST_BOOT_WAIT;
                    end else if (pending_rom_valid_mask[promo_slot]) begin
                        promo_offset <= 15'd0;
                        state        <= ST_PROMO_RD_REQ;
                    end else if (promo_slot == 2'd3) begin
                        state <= ST_PROMO_DRAIN;
                    end else begin
                        promo_slot <= promo_slot + 2'd1;
                    end
                end

                ST_PROMO_RD_REQ: begin
                    if (!clocks_ready || !mem_ready) begin
                        cpu_quiesce      <= 1'b0;
                        media_quiesce    <= 1'b0;
                        boot_error       <= ERR_PROMO_FAIL;
                        boot_commit_done <= 1'b1;
                        state            <= ST_BOOT_WAIT;
                    end else if (promo_mem_accept) begin
                        state <= ST_PROMO_RD_WAIT;
                    end
                end

                ST_PROMO_RD_WAIT: begin
                    if (!clocks_ready || !mem_ready) begin
                        cpu_quiesce      <= 1'b0;
                        media_quiesce    <= 1'b0;
                        boot_error       <= ERR_PROMO_FAIL;
                        boot_commit_done <= 1'b1;
                        state            <= ST_BOOT_WAIT;
                    end else if (promo_mem_rvalid) begin
                        promo_byte <= promo_mem_rdata;
                        state      <= ST_PROMO_WR_REQ;
                    end
                end

                ST_PROMO_WR_REQ: begin
                    if (!clocks_ready || !mem_ready) begin
                        cpu_quiesce      <= 1'b0;
                        media_quiesce    <= 1'b0;
                        boot_error       <= ERR_PROMO_FAIL;
                        boot_commit_done <= 1'b1;
                        state            <= ST_BOOT_WAIT;
                    end else if (promo_mem_accept) begin
                        if (promo_offset + 15'd1 >= ROM_SLOT_BYTES) begin
                            if (promo_slot == 2'd3)
                                state <= ST_PROMO_DRAIN;
                            else begin
                                promo_slot <= promo_slot + 2'd1;
                                state      <= ST_PROMO_CHECK;
                            end
                        end else begin
                            promo_offset <= promo_offset + 15'd1;
                            state        <= ST_PROMO_RD_REQ;
                        end
                    end
                end

                ST_PROMO_DRAIN: begin
                    if (!clocks_ready || !mem_ready) begin
                        cpu_quiesce      <= 1'b0;
                        media_quiesce    <= 1'b0;
                        boot_error       <= ERR_PROMO_FAIL;
                        boot_commit_done <= 1'b1;
                        state            <= ST_BOOT_WAIT;
                    end else if (boot_publish) begin
                        cfg_profile_id     <= pending_profile_id;
                        cfg_ram_size_id    <= pending_ram_size_id;
                        cfg_timing_id      <= pending_timing_id;
                        cfg_paging_id      <= pending_paging_id;
                        cfg_rom_set_id     <= pending_rom_set_id;
                        cfg_rom_valid_mask <= pending_rom_valid_mask;
                        cfg_psg_enable     <= pending_psg_enable;
                        cfg_disk_kind      <= pending_disk_kind;
                        cfg_input_map_id   <= pending_input_map_id;
                        cfg_joy1_b_map     <= pending_joy1_b_map;
                        cfg_joy2_b_map     <= pending_joy2_b_map;
                        cfg_valid          <= 1'b1;
                        boot_overlay       <= 1'b0;
                        sd_owner_boot      <= 1'b0;
                        boot_recovery      <= 1'b0;
                        cpu_quiesce        <= 1'b0;
                        media_quiesce      <= 1'b0;
                        boot_error         <= ERR_OK;
                        boot_commit_done   <= 1'b1;
                        state              <= ST_GUEST_RELEASE;
                    end
                end

                ST_GUEST_RELEASE: begin
                    if (clocks_ready && mem_ready) begin
                        guest_reset_n <= 1'b1;
                        cpu_reset_n   <= 1'b1;
                        state         <= ST_GUEST_RUN;
                    end
                end

                ST_GUEST_RUN: begin
                    if (rec_edge) begin
                        cpu_quiesce   <= 1'b1;
                        media_quiesce <= 1'b1;
                        state         <= ST_RET_QUIESCE;
                    end else if (soft_edge) begin
                        cpu_quiesce   <= 1'b1;
                        media_quiesce <= 1'b1;
                        state         <= ST_SOFT_QUIESCE;
                    end
                end

                ST_SOFT_QUIESCE: begin
                    if (cpu_quiesced && media_idle && mem_idle) begin
                        cpu_reset_n   <= 1'b0;
                        guest_reset_n <= 1'b0;
                        cpu_quiesce   <= 1'b0;
                        media_quiesce <= 1'b0;
                        state         <= ST_GUEST_RELEASE;
                    end
                end

                ST_RET_QUIESCE: begin
                    if (cpu_quiesced && media_idle && mem_idle) begin
                        cpu_reset_n   <= 1'b0;
                        guest_reset_n <= 1'b0;
                        cfg_timing_id <= BOOT_TIMING_ID;
                        boot_overlay  <= 1'b1;
                        sd_owner_boot <= 1'b1;
                        boot_recovery <= 1'b1;
                        cpu_quiesce   <= 1'b0;
                        media_quiesce <= 1'b0;
                        state         <= ST_BOOT_WAIT;
                    end
                end

                default: state <= ST_BOOT_WAIT;
            endcase
        end
    end
endmodule
