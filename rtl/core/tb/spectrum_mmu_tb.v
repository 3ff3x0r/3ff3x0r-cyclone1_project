`timescale 1ns/1ps

module spectrum_mmu_tb;
    reg clk_sys = 0;
    always #5 clk_sys = !clk_sys;

    reg rst_n = 0, run = 0;
    reg [15:0] addr = 0;
    reg port_write = 0, opcode_read = 0;
    reg [5:0] port_data = 0;
    wire is_ram, mapped, screen_bank7, paging_locked, beta_active;
    wire [2:0] ram_bank;
    wire [21:0] physical_addr;

    spectrum_mmu dut (
        .clk_sys(clk_sys), .rst_n(rst_n), .run(run),
        .paging_id(3'd4), .rom_valid_mask(4'b0111), .addr(addr),
        .port_write(port_write), .port_data(port_data),
        .beta_enable(1'b1), .opcode_read(opcode_read),
        .is_ram(is_ram), .ram_bank(ram_bank), .mapped(mapped),
        .physical_addr(physical_addr), .screen_bank7(screen_bank7),
        .paging_locked(paging_locked), .disk_motor(), .beta_active(beta_active)
    );

    task write_port;
        input [15:0] port;
        input [5:0] data;
        begin
            @(negedge clk_sys);
            addr = port;
            port_data = data;
            port_write = 1;
            @(negedge clk_sys);
            port_write = 0;
        end
    endtask

    task fetch_opcode;
        input [15:0] fetch_addr;
        begin
            @(negedge clk_sys);
            addr = fetch_addr;
            opcode_read = 1;
            @(negedge clk_sys);
            opcode_read = 0;
        end
    endtask

    task check_paging;
        input [8*32-1:0] step;
        input [5:0] expected_7ffd;
        input [1:0] expected_rom;
        reg [21:0] expected_addr;
        begin
            addr = 16'hc000;
            expected_addr = 22'h004000 * expected_7ffd[2:0];
            #1;
            if (mapped !== 1'b1 || is_ram !== 1'b1 || ram_bank !== expected_7ffd[2:0] ||
                physical_addr !== expected_addr) begin
                $display("FAIL %0s: C000 expected bank %0d at %06h, got bank %0d at %06h",
                         step, expected_7ffd[2:0], expected_addr, ram_bank, physical_addr);
                $finish;
            end
            if (paging_locked !== expected_7ffd[5] || screen_bank7 !== expected_7ffd[3]) begin
                $display("FAIL %0s: lock/screen 7 expected %b/%b, got %b/%b",
                         step, expected_7ffd[5], expected_7ffd[3], paging_locked, screen_bank7);
                $finish;
            end

            addr = 16'h0000;
            expected_addr = 22'h020000 + 22'h004000 * expected_rom;
            #1;
            if (mapped !== 1'b1 || is_ram !== 1'b0 || physical_addr !== expected_addr ||
                beta_active !== (expected_rom == 2'd2)) begin
                $display("FAIL %0s: 0000 expected ROM at %06h, got %06h (beta_active=%b)",
                         step, expected_addr, physical_addr, beta_active);
                $finish;
            end
        end
    endtask

    initial begin
        @(negedge clk_sys);
        rst_n = 1;
        run = 1;
        write_port(16'h7ffd, 6'h10);
        check_paging("before TR-DOS entry", 6'h10, 2'd1);
        fetch_opcode(16'h3d00);
        check_paging("after TR-DOS entry", 6'h10, 2'd2);

        write_port(16'h7ffd, 6'h0b);
        check_paging("7FFD during TR-DOS", 6'h0b, 2'd2);
        write_port(16'h001f, 6'h34);
        check_paging("Beta register write", 6'h0b, 2'd2);

        // 3FFD aliases 7FFD on Pentagon's partial address decode.
        write_port(16'h3ffd, 6'h25);
        check_paging("lock via 3FFD alias", 6'h25, 2'd2);
        write_port(16'h7ffd, 6'h06);
        check_paging("locked write during TR-DOS", 6'h25, 2'd2);
        fetch_opcode(16'hc000);
        write_port(16'h7ffd, 6'h06);
        check_paging("locked write after TR-DOS exit", 6'h25, 2'd0);

        @(negedge clk_sys);
        run = 0;
        @(negedge clk_sys);
        run = 1;
        check_paging("after guest reset", 6'h00, 2'd0);
        write_port(16'h7ffd, 6'h06);
        check_paging("write after guest reset", 6'h06, 2'd0);

        $display("PASS Pentagon 7FFD paging during TR-DOS, Beta I/O isolation and lock until guest reset");
        $finish;
    end
endmodule
