module boot_bus_adapter #(
    parameter BOOT_ROM_FILE = ""
) (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire        boot_overlay,
    input  wire        mem_ready,

    // Boot CPU bus from core_subsystem
    input  wire        boot_bus_req,
    input  wire        boot_bus_io,
    input  wire        boot_bus_we,
    input  wire [15:0] boot_bus_addr,
    input  wire [7:0]  boot_bus_wdata,
    output reg         boot_bus_ready,
    output reg  [7:0]  boot_bus_rdata,

    // SD bridge I/O response (ports D0h-D5h)
    input  wire        sd_bridge_ready,
    input  wire [7:0]  sd_bridge_rdata,

    // Fabric memory client (muxed onto cpu_mem_* while boot_overlay=1)
    output wire        boot_mem_req,
    input  wire        boot_mem_accept,
    output wire [21:0] boot_mem_addr,
    output wire        boot_mem_we,
    output wire [7:0]  boot_mem_wdata,
    input  wire        boot_mem_rvalid,
    input  wire [7:0]  boot_mem_rdata
);
    (* ramstyle = "M4K" *) reg [7:0] boot_rom [0:4095];
    reg [7:0] rom_q;
    reg       rom_read_done;
    reg       mem_read_wait;

    integer idx;
    initial begin
        for (idx = 0; idx < 4096; idx = idx + 1)
            boot_rom[idx] = 8'h76; // Z80 HALT default
        if (BOOT_ROM_FILE != "") begin
            $readmemh(BOOT_ROM_FILE, boot_rom);
        end else begin
            // Built-in hardware smoke test. LDIR propagates each seed byte
            // across its screen region using overlapping source and destination.
            boot_rom[0]  = 8'hf3;                                             // DI
            boot_rom[1]  = 8'h3e; boot_rom[2]  = 8'h05;                       // LD A,05h (cyan)
            boot_rom[3]  = 8'hd3; boot_rom[4]  = 8'hfe;                       // OUT (FEh),A
            boot_rom[5]  = 8'h21; boot_rom[6]  = 8'h00; boot_rom[7]  = 8'h40; // LD HL,4000h
            boot_rom[8]  = 8'h36; boot_rom[9]  = 8'haa;                       // LD (HL),AAh (vertical stripes)
            boot_rom[10] = 8'h11; boot_rom[11] = 8'h01; boot_rom[12] = 8'h40; // LD DE,4001h
            boot_rom[13] = 8'h01; boot_rom[14] = 8'hff; boot_rom[15] = 8'h17; // LD BC,17FFh
            boot_rom[16] = 8'hed; boot_rom[17] = 8'hb0;                       // LDIR through 57FFh
            boot_rom[18] = 8'h21; boot_rom[19] = 8'h00; boot_rom[20] = 8'h58; // LD HL,5800h
            boot_rom[21] = 8'h36; boot_rom[22] = 8'h4f;                       // LD (HL),4Fh (bright white on blue)
            boot_rom[23] = 8'h11; boot_rom[24] = 8'h01; boot_rom[25] = 8'h58; // LD DE,5801h
            boot_rom[26] = 8'h01; boot_rom[27] = 8'hff; boot_rom[28] = 8'h02; // LD BC,02FFh
            boot_rom[29] = 8'hed; boot_rom[30] = 8'hb0;                       // LDIR through 5AFFh
            boot_rom[31] = 8'h18; boot_rom[32] = 8'hfe;                       // JR $
        end
    end

    wire active      = boot_overlay && boot_bus_req;
    wire is_io       = active && boot_bus_io;
    wire is_mem      = active && !boot_bus_io;
    wire is_sd_io    = is_io && (boot_bus_addr[7:0] >= 8'hd0) && (boot_bus_addr[7:0] <= 8'hd5);
    wire is_rom      = is_mem && (boot_bus_addr[15:12] == 4'h0);
    wire is_bank5    = is_mem && (boot_bus_addr[15:13] == 3'b010);
    wire is_lram     = is_mem && (boot_bus_addr >= 16'h6000);
    wire is_sdram    = is_bank5 || is_lram;

    wire [15:0] lram_offset = boot_bus_addr - 16'h6000;

    assign boot_mem_req   = is_sdram && mem_ready && !mem_read_wait;
    assign boot_mem_we    = boot_bus_we;
    assign boot_mem_wdata = boot_bus_wdata;
    assign boot_mem_addr  = is_bank5
        ? {9'h00a, boot_bus_addr[12:0]}               // 014000-015FFF
        : (22'h040000 + {6'd0, lram_offset});         // 040000-049FFF

    // Synchronous M4K read for on-chip boot ROM
    always @(posedge clk_sys) begin
        rom_q <= boot_rom[boot_bus_addr[11:0]];
    end

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            rom_read_done <= 1'b0;
            mem_read_wait <= 1'b0;
        end else begin
            if (!boot_overlay || !boot_bus_req) begin
                rom_read_done <= 1'b0;
                mem_read_wait <= 1'b0;
            end else begin
                if (is_rom && !boot_bus_we)
                    rom_read_done <= !rom_read_done;
                else
                    rom_read_done <= 1'b0;

                if (boot_mem_req && boot_mem_accept && !boot_bus_we)
                    mem_read_wait <= 1'b1;
                else if (mem_read_wait && boot_mem_rvalid)
                    mem_read_wait <= 1'b0;
            end
        end
    end

    always @* begin
        boot_bus_ready = 1'b0;
        boot_bus_rdata = 8'hff;
        if (active) begin
            if (is_io) begin
                if (is_sd_io) begin
                    boot_bus_ready = sd_bridge_ready;
                    boot_bus_rdata = sd_bridge_rdata;
                end else begin
                    boot_bus_ready = 1'b1;
                    boot_bus_rdata = 8'hff;
                end
            end else if (is_rom) begin
                if (boot_bus_we) begin
                    boot_bus_ready = 1'b1;
                end else begin
                    boot_bus_ready = rom_read_done;
                    boot_bus_rdata = rom_q;
                end
            end else if (is_sdram) begin
                if (boot_bus_we) begin
                    boot_bus_ready = boot_mem_req && boot_mem_accept;
                end else begin
                    boot_bus_ready = mem_read_wait && boot_mem_rvalid;
                    boot_bus_rdata = boot_mem_rdata;
                end
            end else begin
                // Unmapped 1000-3FFF
                boot_bus_ready = 1'b1;
                boot_bus_rdata = 8'hff;
            end
        end
    end
endmodule
