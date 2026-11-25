`timescale 1ns/1ps

module boot_bus_adapter_tb;
    reg clk_sys = 1'b0;
    always #5 clk_sys = ~clk_sys;

    reg        rst_n = 1'b0;
    reg        boot_overlay = 1'b1;
    reg        mem_ready = 1'b1;
    reg        boot_bus_req = 1'b0;
    reg        boot_bus_io = 1'b0;
    reg        boot_bus_we = 1'b0;
    reg [15:0] boot_bus_addr = 16'h0000;
    reg [7:0]  boot_bus_wdata = 8'h00;
    wire       boot_bus_ready;
    wire [7:0] boot_bus_rdata;

    reg        sd_bridge_ready = 1'b1;
    reg [7:0]  sd_bridge_rdata = 8'h5a;

    wire        boot_mem_req;
    wire        boot_mem_accept;
    wire [21:0] boot_mem_addr;
    wire        boot_mem_we;
    wire [7:0]  boot_mem_wdata;
    reg         boot_mem_rvalid = 1'b0;
    reg  [7:0]  boot_mem_rdata = 8'h00;

    boot_bus_adapter dut (
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

    reg [21:0] last_addr = 22'd0;
    reg [7:0]  last_wdata = 8'd0;
    assign boot_mem_accept = boot_mem_req;

    always @(posedge clk_sys) begin
        boot_mem_rvalid <= 1'b0;
        if (boot_mem_req && boot_mem_accept) begin
            last_addr <= boot_mem_addr;
            if (boot_mem_we)
                last_wdata <= boot_mem_wdata;
            else begin
                boot_mem_rvalid <= 1'b1;
                boot_mem_rdata  <= boot_mem_addr[7:0] ^ 8'h3c;
            end
        end
    end

    task tick;
        begin
            @(posedge clk_sys);
            #1;
        end
    endtask

    initial begin
        tick; tick;
        rst_n = 1'b1;
        tick;

        // 1. Boot ROM read at 0000 (expects default 76h on next cycle)
        boot_bus_req = 1'b1; boot_bus_io = 1'b0; boot_bus_we = 1'b0; boot_bus_addr = 16'h0000;
        #1;
        if (boot_bus_ready) begin $display("FAIL ROM ready too early"); $finish; end
        tick;
        if (!boot_bus_ready || boot_bus_rdata !== 8'h76) begin
            $display("FAIL ROM read: ready=%b data=%h", boot_bus_ready, boot_bus_rdata);
            $finish;
        end
        boot_bus_req = 1'b0; tick;

        // 2. Unmapped 1000-3FFF returns FF immediately
        boot_bus_req = 1'b1; boot_bus_addr = 16'h2345;
        #1;
        if (!boot_bus_ready || boot_bus_rdata !== 8'hff) begin
            $display("FAIL unmapped read: ready=%b data=%h", boot_bus_ready, boot_bus_rdata);
            $finish;
        end
        boot_bus_req = 1'b0; tick;

        // 3. Bank 5 write at 4123 -> fabric 014123
        boot_bus_req = 1'b1; boot_bus_we = 1'b1; boot_bus_addr = 16'h4123; boot_bus_wdata = 8'haa;
        #1;
        if (!boot_bus_ready || boot_mem_addr !== 22'h014123) begin
            $display("FAIL bank5 write: ready=%b addr=%h", boot_bus_ready, boot_mem_addr);
            $finish;
        end
        tick;
        boot_bus_req = 1'b0; tick;

        // 4. Loader RAM read at 6005 -> fabric 040005
        boot_bus_req = 1'b1; boot_bus_we = 1'b0; boot_bus_addr = 16'h6005;
        #1;
        if (boot_mem_addr !== 22'h040005) begin
            $display("FAIL lram addr: %h", boot_mem_addr);
            $finish;
        end
        tick;
        if (!boot_bus_ready || boot_bus_rdata !== (8'h05 ^ 8'h3c)) begin
            $display("FAIL lram read: ready=%b data=%h", boot_bus_ready, boot_bus_rdata);
            $finish;
        end
        boot_bus_req = 1'b0; tick;

        // 5. SD I/O port D4h routes to sd_bridge
        boot_bus_req = 1'b1; boot_bus_io = 1'b1; boot_bus_we = 1'b0; boot_bus_addr = 16'h00d4;
        #1;
        if (!boot_bus_ready || boot_bus_rdata !== 8'h5a) begin
            $display("FAIL SD IO route: ready=%b data=%h", boot_bus_ready, boot_bus_rdata);
            $finish;
        end

        $display("PASS boot_bus_adapter: ROM, unmapped, bank5, loader RAM, and SD IO routing");
        $finish;
    end
endmodule
