// One active transfer and one pending slot, in global acceptance order.
// A CPU request can claim the pending slot during an active transfer.
// The loader can enter only at dispatch, so it cannot fill that slot ahead
// of a future CPU request while the controller is busy.
module mem_arbiter (
    input  wire        clk_sys,
    input  wire        rst_n,
    input  wire        mem_ready,
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

    output wire        issue_req,
    input  wire        issue_accept,
    output wire [21:0] issue_addr,
    output wire        issue_we,
    output wire [7:0]  issue_wdata,
    input  wire        issue_busy,
    input  wire        issue_rvalid,
    input  wire [7:0]  issue_rdata
);
    reg        pending;
    reg        pending_loader;
    reg [21:0] pending_addr;
    reg        pending_we;
    reg [7:0]  pending_wdata;
    reg        active_loader;

    assign cpu_mem_accept = mem_ready && (!pending || issue_accept);
    assign ld_mem_accept = mem_ready && issue_accept && !pending;
    wire take_cpu = cpu_mem_req && cpu_mem_accept;
    wire take_loader = ld_mem_req && ld_mem_accept;

    assign issue_req = pending || take_cpu || take_loader;
    assign issue_addr = pending ? pending_addr : (take_cpu ? cpu_mem_addr : ld_mem_addr);
    assign issue_we = pending ? pending_we : (take_cpu ? cpu_mem_we : ld_mem_we);
    assign issue_wdata = pending ? pending_wdata : (take_cpu ? cpu_mem_wdata : ld_mem_wdata);

    assign cpu_mem_rvalid = issue_rvalid && !active_loader;
    assign ld_mem_rvalid = issue_rvalid && active_loader;
    assign cpu_mem_rdata = issue_rdata;
    assign ld_mem_rdata = issue_rdata;
    assign mem_idle = mem_ready && !pending && !issue_busy && !issue_rvalid;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 1'b0;
            pending_loader <= 1'b0;
            pending_addr <= 22'b0;
            pending_we <= 1'b0;
            pending_wdata <= 8'b0;
            active_loader <= 1'b0;
        end else begin
            if (issue_accept && issue_req) begin
                active_loader <= pending ? pending_loader : !take_cpu;
                pending <= 1'b0;
            end

            if (take_cpu && (pending || !issue_accept)) begin
                pending <= 1'b1;
                pending_loader <= 1'b0;
                pending_addr <= cpu_mem_addr;
                pending_we <= cpu_mem_we;
                pending_wdata <= cpu_mem_wdata;
            end else if (take_cpu && take_loader) begin
                pending <= 1'b1;
                pending_loader <= 1'b1;
                pending_addr <= ld_mem_addr;
                pending_we <= ld_mem_we;
                pending_wdata <= ld_mem_wdata;
            end
        end
    end
endmodule
