`ifndef TRHMSX_FIT_LINT
`timescale 1ps/1ps

module trhmsx_mem_fit_tb;
    reg clk_21m = 0;
    always #23280 clk_21m = ~clk_21m;

    reg cart_reset_n = 1;
    wire sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n;
    wire [12:0] sdram_a;
    wire [1:0] sdram_ba, sdram_dqm;
    wire [15:0] sdram_dq;
    wire [5:0] vga_r, vga_g, vga_b;
    wire [3:0] sdram_command = {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n};

    trhmsx_mem_fit_top dut (
        .clk_21m(clk_21m), .cart_reset_n(cart_reset_n),
        .sdram_clk(sdram_clk), .sdram_cke(sdram_cke), .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n), .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_a(sdram_a), .sdram_ba(sdram_ba), .sdram_dqm(sdram_dqm), .sdram_dq(sdram_dq),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b)
    );

    // The fit top exercises the lower 4 MiB of the x16 device.
    sdram_x16_model #(.ROW_BITS(10)) chip (
        .rst_n(dut.rst_n), .clk(sdram_clk), .cke(sdram_cke), .cs_n(sdram_cs_n),
        .ras_n(sdram_ras_n), .cas_n(sdram_cas_n), .we_n(sdram_we_n),
        .a(sdram_a), .ba(sdram_ba), .dqm(sdram_dqm), .dq(sdram_dq),
        .column_word_addr()
    );

    localparam SCREEN_READS = 2 * 6912;
    localparam [7:0] RESET_CPU_BYTE = 8'ha0, RESET_LOADER_BYTE = 8'h5f;
    integer received = 0, checked = 0;
    integer inject_at = 0;
    reg injected = 0;
    reg pending = 0, expected_failure = 0;
    reg awaiting_fresh_capture = 0;
    reg comparing_last, expected_idle;
    reg [7:0] corrupt_data, previous_data, previous_expected, reference_byte, pattern;

    // The next READ is registered on T0. Find its expected fabric sample
    // from the SDRAM clock rather than from the DUT's read pipeline.
    task wait_read_capture;
        begin
            @(posedge sdram_clk);
            while (sdram_command !== 4'b0101)
                @(posedge sdram_clk);
            repeat (2) @(posedge sdram_clk);
            @(negedge dut.clk_sys);
            #1;
        end
    endtask

    initial begin
        if ($test$plusargs("inject_first"))
            inject_at = 1;
        if ($test$plusargs("inject_last"))
            inject_at = SCREEN_READS;
        #1000 cart_reset_n = 0;
        #100000 cart_reset_n = 1;

        // At offset zero the clients read distinct bytes. Reset after
        // capturing the loader's byte but before
        // the following rising edge can publish it.
        wait (dut.cpu_mem_rvalid);
        wait_read_capture;
        if (dut.memory.controller.captured_dq[7:0] !== RESET_LOADER_BYTE ||
            dut.ld_mem_rvalid !== 1'b0 || dut.ld_read_done !== 1'b0)
            $fatal(1, "Reset must interrupt a captured, unpublished loader read");
        awaiting_fresh_capture = 1;
        cart_reset_n = 0;
        #1;
        if ({dut.rst_n, dut.mem_ready, dut.cpu_mem_rvalid, dut.ld_mem_rvalid} !== 4'b0 ||
            dut.memory.controller.captured_dq[7:0] !== RESET_LOADER_BYTE)
            $fatal(1, "Reset must cancel the pending read and leave the DQ sample alone");

        repeat (4) @(negedge dut.clk_sys);
        #1 cart_reset_n = 1;
        wait_read_capture;
        if (dut.memory.controller.captured_dq[7:0] !== RESET_CPU_BYTE)
            $fatal(1, "First READ after reset captured the wrong byte");
        awaiting_fresh_capture = 0;
        @(posedge dut.clk_sys);
        #1;
        if ({dut.cpu_mem_rvalid, dut.ld_mem_rvalid, dut.cpu_mem_rdata} !== {2'b10, RESET_CPU_BYTE})
            $fatal(1, "First response after reset must be the CPU's fresh byte");
        @(posedge dut.clk_sys);
        #1;
        if ({dut.cpu_mem_rvalid, dut.ld_mem_rvalid} !== 2'b00)
            $fatal(1, "First post-reset response lasted more than one clock");
        $display("PASS reset during read: cancelled loader %h, first new CPU response %h",
            RESET_LOADER_BYTE, RESET_CPU_BYTE);
    end

    always @(posedge dut.clk_sys) begin
        #1;
        if (awaiting_fresh_capture && {dut.cpu_mem_rvalid, dut.ld_mem_rvalid} !== 2'b00)
            $fatal(1, "Unexpected read response before a fresh post-reset DQ sample");
    end

    initial begin
        #10000000000;
        $fatal(1, "Fit-top screen sweep timed out");
    end

    always @(negedge dut.clk_sys) begin
        if (dut.rst_n && dut.screen_rd_valid && received + 1 == inject_at) begin
            corrupt_data = dut.screen_rd_data ^ 8'h80;
            force dut.screen_rd_data = corrupt_data;
            injected = 1;
            @(negedge dut.clk_sys);
            release dut.screen_rd_data;
        end
    end

    always @(posedge dut.clk_sys) begin
        if (dut.rst_n) begin
            comparing_last = pending && checked == SCREEN_READS - 1;
            if (dut.screen_check_valid !== pending)
                $fatal(1, "Screen check-valid is misaligned with the previous return");
            if (pending) begin
                if (dut.screen_sample !== previous_data ||
                    dut.screen_check_expected !== previous_expected)
                    $fatal(1, "Screen comparison operands are misaligned");
                if (previous_data !== previous_expected)
                    expected_failure = 1;
                checked = checked + 1;
            end

            pending = dut.screen_rd_valid;
            if (pending) begin
                if (int'(dut.offset) != received / 2 || dut.screen_rd_bank7 !== received[0])
                    $fatal(1, "Unexpected screen offset or bank");
                received = received + 1;
                pattern = dut.offset[7:0] ^ {3'b101, dut.offset[12:8]};
                reference_byte = (dut.screen_rd_bank7 == dut.offset[1]) ? pattern : ~pattern;
                previous_data = dut.screen_rd_data;
                previous_expected = reference_byte;
                if (previous_data !== (received == inject_at ? reference_byte ^ 8'h80 : reference_byte))
                    $fatal(1, "Unexpected mirror data at return %0d", received);
            end

            #1;
            if (dut.test_failed !== expected_failure)
                $fatal(1, "Incorrect sticky failure after %0d comparisons", checked);
            if (comparing_last && dut.general_sweep)
                $fatal(1, "Sweep completion coincided with the final comparison");
        end
    end

    initial begin
        wait (dut.general_sweep);
        // Observe the sweep transition after the registers have settled.
        @(negedge dut.clk_sys);
        if (received != SCREEN_READS || checked != SCREEN_READS ||
            dut.screen_check_valid !== 1'b0 || pending ||
            injected !== (inject_at != 0) || dut.test_failed !== (inject_at != 0))
            $fatal(1, "The screen sweep completed before the final check retired");
        @(posedge dut.clk_sys);
        while (!dut.visible || dut.pixel_phase != 2'd3)
            @(posedge dut.clk_sys);
        expected_idle = dut.mem_idle;
        #1;
        if (vga_r[5] !== (inject_at != 0) || vga_g[5] !== 1'b1 || vga_b[5] !== expected_idle ||
            vga_b[4:0] !== (previous_data[4:0] ^ {previous_data[7:5], 2'b00}))
            $fatal(1, "Incorrect VGA failure, ready or mirror sample");
        $display("PASS fit top: %0d mirror comparisons, injected return %0d, sticky failure %b",
            checked, inject_at, dut.test_failed);
        $finish;
    end
endmodule
`endif

// Local ALTPLL stub. Simulation uses the nominal requested phase and
// frequency. It does not model fitted PLL quantization or pin delays.
/* verilator lint_off DECLFILENAME */
module altpll #(
    /* verilator lint_off UNUSEDPARAM */
    parameter intended_device_family = "",
    parameter operation_mode = "",
    parameter compensate_clock = "",
    parameter inclk0_input_frequency = 1,
    parameter clk0_multiply_by = 1,
    parameter clk0_divide_by = 1,
    parameter clk0_duty_cycle = 50,
    parameter clk0_phase_shift = "0",
    parameter extclk0_multiply_by = 1,
    parameter extclk0_divide_by = 1,
    parameter extclk0_duty_cycle = 50,
    parameter extclk0_phase_shift = "0",
    parameter width_clock = 6,
    parameter port_inclk0 = "",
    parameter port_areset = "",
    parameter port_locked = "",
    parameter port_clk0 = "",
    parameter port_extclk0 = ""
    /* verilator lint_on UNUSEDPARAM */
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input wire [1:0] inclk,
    /* verilator lint_on UNUSEDSIGNAL */
    input wire areset,
    output wire [width_clock-1:0] clk,
    output wire [3:0] extclk,
    output wire locked
);
`ifdef TRHMSX_FIT_LINT
    wire fabric_clk = inclk[0];
    wire pin_clk = inclk[0];
`else
    localparam HALF_PERIOD_PS = inclk0_input_frequency * clk0_divide_by / clk0_multiply_by / 2;
    reg fabric_clk = 0, pin_clk = 0;
    integer pin_phase_ps;
    always #(HALF_PERIOD_PS) fabric_clk = ~fabric_clk;
    initial begin
        if (clk0_phase_shift != "0" || clk0_duty_cycle != 50 || extclk0_duty_cycle != 50 ||
            extclk0_multiply_by * clk0_divide_by != clk0_multiply_by * extclk0_divide_by)
            $fatal(1, "Fit test requires equal-frequency, 50%% duty PLL outputs and zero c0 phase");
        if ($sscanf(extclk0_phase_shift, "%d", pin_phase_ps) != 1 ||
            HALF_PERIOD_PS + pin_phase_ps <= 0)
            $fatal(1, "Unsupported SDRAM pin clock phase");
        #(HALF_PERIOD_PS + pin_phase_ps);
        forever begin
            pin_clk = ~pin_clk;
            #(HALF_PERIOD_PS);
        end
    end
`endif
    assign clk = {{(width_clock-1){1'b0}}, fabric_clk};
    assign extclk = {3'b0, pin_clk};
    assign locked = ~areset;
endmodule
/* verilator lint_on DECLFILENAME */
