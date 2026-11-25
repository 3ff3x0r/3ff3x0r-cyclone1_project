module core_subsystem (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire        cpu_reset_n,
    input  wire        guest_reset_n,
    input  wire        cpu_quiesce,
    output wire        cpu_quiesced,
    input  wire        boot_overlay,
    input  wire        cfg_valid,
    input  wire [2:0]  cfg_timing_id,
    input  wire [2:0]  cfg_paging_id,
    input  wire [3:0]  cfg_rom_valid_mask,
    input  wire        cfg_psg_enable,
    input  wire [1:0]  cfg_disk_kind,
    input  wire [1:0]  cfg_input_map_id,
    input  wire [1:0]  cfg_joy1_b_map,
    input  wire [1:0]  cfg_joy2_b_map,
    input  wire        ce_cpu,
    input  wire        ce_ula,
    input  wire        ce_psg,
    output wire        psg_ce,

    input  wire        mem_ready,
    output wire        cpu_mem_req,
    input  wire        cpu_mem_accept,
    output wire [21:0] cpu_mem_addr,
    output wire        cpu_mem_we,
    output wire [7:0]  cpu_mem_wdata,
    input  wire        cpu_mem_rvalid,
    input  wire [7:0]  cpu_mem_rdata,
    output reg         cpu_mem_deadline_miss,

    output wire        boot_bus_req,
    output wire        boot_bus_io,
    output wire        boot_bus_we,
    output wire [15:0] boot_bus_addr,
    output wire [7:0]  boot_bus_wdata,
    input  wire        boot_bus_ready,
    input  wire [7:0]  boot_bus_rdata,

    output wire        screen_rd_req,
    output wire        screen_rd_bank7,
    output wire [12:0] screen_rd_offset,
    input  wire        screen_rd_valid,
    input  wire [7:0]  screen_rd_data,
    output wire        ula_px_ce,
    output wire [3:0]  ula_color,
    output wire [9:0]  ula_x,
    output wire [8:0]  ula_y,
    output wire        ula_hs_n,
    output wire        ula_vs_n,
    output wire        ula_blank,

    input  wire [39:0] key_matrix_n,
    input  wire [5:0]  joy1,
    input  wire [5:0]  joy2,
    input  wire        ear_bit,
    output wire        mic_bit,
    output wire        beeper_bit,
    output wire        ay_req,
    output wire [1:0]  ay_op,
    output wire [7:0]  ay_wdata,
    input  wire [7:0]  ay_rdata,

    output wire        disk_req,
    output wire        disk_we,
    output wire [2:0]  disk_reg,
    output wire [7:0]  disk_wdata,
    input  wire [7:0]  disk_rdata,
    output wire        disk_motor
);
    wire cpu_on = rst_n && cpu_reset_n && (boot_overlay || guest_reset_n);
    wire guest_on = cpu_on && !boot_overlay && cfg_valid;
    wire guest_state_n = rst_n && guest_reset_n && !boot_overlay;
    wire [2:0] timing_id = cfg_valid && !boot_overlay ? cfg_timing_id : 3'd0;
    wire is_plus3 = cfg_paging_id == 3'd3;
    wire is_tk = timing_id == 3'd3 || timing_id == 3'd4;

    wire [15:0] addr;
    wire [7:0] cpu_DO;
    reg [7:0] cpu_DI;
    wire m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
    wire cpu_ce_p, cpu_ce_n, ula_int_n;
    wire memory_cycle = !mreq_n && rfsh_n;
    wire mem_read = memory_cycle && !rd_n;
    wire mem_write = memory_cycle && !wr_n;
    wire io_cycle = !iorq_n && m1_n && (!rd_n || !wr_n);
    wire bus_busy = memory_cycle || io_cycle || !iorq_n;
    wire access_cycle = mem_read || mem_write || io_cycle;

    wire ula_bus_valid = guest_on && (memory_cycle || io_cycle);
    wire ula_bus_is_ram;
    wire [2:0] ula_bus_ram_bank;
    reg [2:0] ula_contend_id;
    always @* begin
        case (timing_id)
            3'd1: ula_contend_id = 3'd2;
            3'd2: ula_contend_id = 3'd3;
            3'd3: ula_contend_id = 3'd4;
            3'd4: ula_contend_id = 3'd5;
            3'd5: ula_contend_id = 3'd0;
            default: ula_contend_id = 3'd1;
        endcase
    end

    wire mapped, screen_bank7, paging_locked, beta_active;
    wire [21:0] physical_addr;
    wire io_done;
    spectrum_mmu mmu (
        .clk_sys(clk_sys), .reset_n(guest_state_n), .paging_id(cfg_paging_id),
        .rom_valid_mask(cfg_rom_valid_mask), .addr(addr),
        .port_write(io_done && !wr_n), .port_data(cpu_DO[5:0]),
        .beta_enable(cfg_disk_kind == 2'd2 && cfg_paging_id == 3'd4 &&
                     cfg_rom_valid_mask[2]),
        .opcode_read(guest_on && mem_read && !m1_n),
        .is_ram(ula_bus_is_ram), .ram_bank(ula_bus_ram_bank), .mapped(mapped),
        .physical_addr(physical_addr), .screen_bank7(screen_bank7),
        .paging_locked(paging_locked), .disk_motor(disk_motor), .beta_active(beta_active)
    );

    // A request is visible on the first fabric edge after T80pa asserts
    // RD or WR. The phase controls keep the CPU payload stable until take.
    reg access_taken;
    reg read_pending;
    reg read_done;
    reg [7:0] read_data;
    wire guest_access = guest_on && mapped && (mem_read || (mem_write && ula_bus_is_ram));
    wire boot_access = cpu_on && boot_overlay && access_cycle;
    assign cpu_mem_req = guest_access && !access_taken && !read_pending;
    assign cpu_mem_addr = physical_addr;
    assign cpu_mem_we = cpu_mem_req && mem_write;
    assign cpu_mem_wdata = mem_write ? cpu_DO : 8'd0;
    assign boot_bus_req = boot_access && !access_taken;
    assign boot_bus_io = boot_bus_req && io_cycle;
    assign boot_bus_we = boot_bus_req && !wr_n;
    assign boot_bus_addr = addr;
    assign boot_bus_wdata = boot_bus_we ? cpu_DO : 8'd0;
    wire mem_take = cpu_mem_req && cpu_mem_accept;
    wire boot_take = boot_bus_req && boot_bus_ready;
    wire live_response = guest_access && access_taken && read_pending && cpu_mem_rvalid;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            read_pending <= 1'b0;
        else if (mem_take && !cpu_mem_we)
            read_pending <= 1'b1;
        else if (cpu_mem_rvalid)
            read_pending <= 1'b0;
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            access_taken <= 1'b0;
            read_done <= 1'b0;
            read_data <= 8'hff;
        end else if (!cpu_on || !access_cycle) begin
            access_taken <= 1'b0;
            read_done <= 1'b0;
        end else begin
            if (mem_take || boot_take)
                access_taken <= 1'b1;
            if (live_response || (boot_take && !boot_bus_we)) begin
                read_done <= 1'b1;
                read_data <= live_response ? cpu_mem_rdata : boot_bus_rdata;
            end
        end
    end

    wire bus_contended;
    wire [2:0] raster_delay;
    wire [7:0] floating_bus, asic_bus, io_rdata;
    reg [2:0] delay_now, delay_prev;
    reg [2:0] mem_wait, io_wait, io_stage;
    reg mem_checked, io_resume, cpu_high;
    reg [1:0] mem_age, io_age;

    // ce_cpu is the positive half of T80pa's bus clock. The interleaved
    // ULA tick provides its negative half. Suppressing a half keeps the
    // phase pending and omits whole T-states from CPU time only.
    wire pos_phase = ce_cpu && !cpu_high;
    wire neg_phase = ce_ula && !ce_cpu && cpu_high;
    wire hold_idle = !bus_busy && (cpu_quiesce || (!boot_overlay && (!cfg_valid || !mem_ready)));
    wire cpu_clock_run = cpu_on && !hold_idle;
    assign cpu_quiesced = cpu_quiesce && (!cpu_on || !bus_busy) && !read_pending;
    wire boot_wait = boot_access && !access_taken && !boot_take;

    // For memory, the address/strobe identify T1 before the next positive
    // edge. For I/O, IORQ starts at T2 and the saved T1 slot is still available.
    wire mem_delay = memory_cycle && (mem_wait != 3'd0 ||
                     (!mem_checked && bus_contended && delay_now != 3'd0));
    wire io_ula_enabled = guest_on && (ula_contend_id == 3'd1 || ula_contend_id == 3'd2 || is_tk);
    wire io_early = io_stage == 3'd0 && bus_contended && delay_prev != 3'd0;
    wire io_late = io_stage < 3'd4 &&
                   (io_stage < 3'd2 ? (!addr[0] || bus_contended) : (addr[0] && bus_contended));
    wire [2:0] new_io_wait = io_early ? delay_prev : io_late ? delay_now : 3'd0;
    wire io_delay = io_cycle && io_ula_enabled &&
                    (io_wait != 3'd0 || (!io_resume && new_io_wait != 3'd0));

    // M1 and the final opcode byte of DD/FD CB instructions use the
    // direct data input on this edge. Ordinary operands are latched on
    // the following negative half, so use this earlier deadline for all.
    wire mem_read_due = mem_read && pos_phase && mem_age == 2'd1;
    wire mem_write_due = mem_write && neg_phase && mem_age == 2'd1;
    wire mem_result_ready = read_done || live_response;
    wire late_read = guest_access && mem_read_due && !mem_result_ready;
    wire late_write = guest_access && mem_write_due && !access_taken && !mem_take;
    assign cpu_ce_p = cpu_clock_run && pos_phase && !mem_delay && !boot_wait && !late_read;
    assign cpu_ce_n = cpu_clock_run && neg_phase && !io_delay && !boot_wait && !late_read && !late_write;
    assign io_done = guest_on && io_cycle && cpu_ce_n && io_age == 2'd2;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            cpu_high <= 1'b0;
            mem_age <= 2'd0;
            io_age <= 2'd0;
            cpu_mem_deadline_miss <= 1'b0;
        end else begin
            if (!cpu_on)
                cpu_high <= 1'b0;
            else if (cpu_ce_p || cpu_ce_n)
                cpu_high <= cpu_ce_p;

            if (!cpu_on || !(mem_read || mem_write))
                mem_age <= 2'd0;
            else if (cpu_ce_p && mem_age != 2'd3)
                mem_age <= mem_age + 2'd1;
            if (!cpu_on || !io_cycle)
                io_age <= 2'd0;
            else if (cpu_ce_n && io_age != 2'd3)
                io_age <= io_age + 2'd1;

            if ((late_read || late_write) && !mem_delay)
                cpu_mem_deadline_miss <= 1'b1;
        end
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            delay_now <= 3'd0;
            delay_prev <= 3'd0;
            mem_wait <= 3'd0;
            mem_checked <= 1'b0;
            io_wait <= 3'd0;
            io_stage <= 3'd0;
            io_resume <= 1'b0;
        end else begin
            if (ce_cpu) begin
                delay_now <= raster_delay;
                delay_prev <= delay_now;
            end
            if (!guest_on || !memory_cycle) begin
                mem_wait <= 3'd0;
                mem_checked <= 1'b0;
            end else if (pos_phase) begin
                if (mem_wait != 3'd0)
                    mem_wait <= mem_wait - 3'd1;
                else if (!mem_checked && bus_contended && delay_now != 3'd0)
                    mem_wait <= delay_now - 3'd1;
                mem_checked <= 1'b1;
            end

            if (!guest_on || !io_cycle) begin
                io_wait <= 3'd0;
                io_stage <= 3'd0;
                io_resume <= 1'b0;
            end else if (neg_phase && io_ula_enabled) begin
                if (io_wait != 3'd0)
                    io_wait <= io_wait - 3'd1;
                else if (io_resume)
                    io_resume <= 1'b0;
                else if (io_stage < 3'd4) begin
                    if (new_io_wait != 3'd0)
                        io_wait <= new_io_wait - 3'd1;
                    io_resume <= !io_early && new_io_wait != 3'd0;
                    io_stage <= io_stage == 3'd0 && !io_early ? 3'd2 : io_stage + 3'd1;
                end
            end
        end
    end

    always @* begin
        cpu_DI = 8'hff;
        if (boot_access && (mem_read || (io_cycle && wr_n))) begin
            if (boot_take)
                cpu_DI = boot_bus_rdata;
            else if (read_done)
                cpu_DI = read_data;
        end else if (guest_on) begin
            if (mem_read) begin
                if (!mapped)
                    cpu_DI = is_plus3 ? 8'hff : floating_bus;
                else if (live_response)
                    cpu_DI = cpu_mem_rdata;
                else if (read_done)
                    cpu_DI = read_data;
            end else if (io_cycle && wr_n) begin
                cpu_DI = io_rdata;
            end
        end
    end

    spectrum_cpu cpu (
        .clk_sys(clk_sys), .reset_n(cpu_on), .ce_p(cpu_ce_p), .ce_n(cpu_ce_n),
        .int_n(boot_overlay || ula_int_n), .m1_n(m1_n), .mreq_n(mreq_n),
        .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(rfsh_n), .addr(addr),
        .data_in(cpu_DI), .data_out(cpu_DO)
    );

    wire [2:0] border;
    spectrum_ula ula (
        .clk_sys(clk_sys), .rst_n(rst_n), .run(boot_overlay || guest_reset_n),
        .ce_cpu(ce_cpu), .ce_ula(ce_ula), .timing_id(timing_id),
        .border(boot_overlay ? 3'd0 : border), .screen_bank7(!boot_overlay && screen_bank7),
        .screen_rd_req(screen_rd_req), .screen_rd_bank7(screen_rd_bank7),
        .screen_rd_offset(screen_rd_offset), .screen_rd_valid(screen_rd_valid),
        .screen_rd_data(screen_rd_data), .ula_px_ce(ula_px_ce), .ula_color(ula_color),
        .ula_x(ula_x), .ula_y(ula_y), .ula_hs_n(ula_hs_n), .ula_vs_n(ula_vs_n),
        .ula_blank(ula_blank), .int_n(ula_int_n), .ula_bus_valid(ula_bus_valid),
        .ula_bus_is_ram(ula_bus_is_ram), .ula_bus_ram_bank(ula_bus_ram_bank),
        .ula_contend_id(ula_contend_id), .bus_contended(bus_contended), .raster_delay(raster_delay),
        .contended_transfer(is_plus3 && bus_contended &&
                            ((mem_read_due && cpu_ce_p) || (mem_write_due && cpu_ce_n))),
        .transfer_data(mem_write ? cpu_DO : cpu_DI), .floating_bus(floating_bus),
        .asic_bus(asic_bus)
    );

    assign psg_ce = ce_psg && guest_state_n && cfg_valid && cfg_psg_enable;
    assign ay_wdata = cpu_DO;
    assign disk_wdata = cpu_DO;
    spectrum_io io (
        .clk_sys(clk_sys), .reset_n(guest_state_n), .addr(addr), .wdata(cpu_DO[4:0]),
        .cycle_done(io_done), .write_cycle(!wr_n), .is_tk(is_tk), .is_plus3(is_plus3),
        .paging_locked(paging_locked), .floating_bus(floating_bus), .asic_bus(asic_bus),
        .key_matrix_n(key_matrix_n), .joy1(joy1), .joy2(joy2), .cfg_input_map_id(cfg_input_map_id),
        .cfg_joy1_b_map(cfg_joy1_b_map), .cfg_joy2_b_map(cfg_joy2_b_map), .ear_bit(ear_bit),
        .border(border), .mic_bit(mic_bit), .beeper_bit(beeper_bit), .cfg_psg_enable(cfg_psg_enable),
        .ay_req(ay_req), .ay_op(ay_op), .ay_rdata(ay_rdata), .plus3_disk(is_plus3 && cfg_disk_kind == 2'd1),
        .beta_active(beta_active), .disk_req(disk_req), .disk_we(disk_we), .disk_reg(disk_reg),
        .disk_rdata(disk_rdata), .rdata(io_rdata)
    );
endmodule
