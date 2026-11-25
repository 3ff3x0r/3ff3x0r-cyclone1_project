`timescale 1ns/1ps
module boot_sd_bridge_tb;
    localparam [31:0] FIRST_LBA = 32'h1234abcd, RETRY_LBA = 32'h86fedcba;
    localparam [7:0] LBA0 = 8'hd0, LBA1 = 8'hd1, LBA2 = 8'hd2, LBA3 = 8'hd3,
        CONTROL = 8'hd4, DATA = 8'hd5;

    reg clk = 0;
    always #5 clk = !clk;
    reg rst_n = 0, sd_owner_boot = 1, quiesce = 0;
    reg cpu_req = 0, cpu_io = 0, cpu_we = 0;
    reg [15:0] cpu_addr = 0;
    reg [7:0] cpu_wdata = 0;
    wire cpu_ready, bridge_idle, sd_idle;
    wire [7:0] cpu_rdata;

    reg permit_command = 1, corrupt_crc = 0, drop_final_byte = 0, omit_token = 0;
    wire sd_req, sd_ready, sd_we, sd_tx_valid, sd_rx_valid, sd_rx_ready, sd_done;
    wire [31:0] sd_lba;
    wire [7:0] sd_tx_data, sd_rx_data;
    wire [3:0] sd_error;
    wire cs_n, sck, mosi;
    reg miso = 1;
    integer accepts = 0, streamed_bytes = 0, cmd0_count = 0, cmd17_count = 0;
    reg [31:0] expected_lba;
    wire server_req = sd_owner_boot && permit_command && sd_req;
    wire server_ready = sd_owner_boot && permit_command && sd_ready;
    wire bridge_rx_valid = sd_rx_valid && !(drop_final_byte && streamed_bytes == 511);
    wire server_quiesce = quiesce && bridge_idle;
    wire media_idle = bridge_idle && sd_idle;

    boot_sd_bridge bridge (
        .clk_sys(clk), .rst_n(rst_n), .sd_owner_boot(sd_owner_boot),
        .media_quiesce(quiesce), .boot_sd_idle(bridge_idle),
        .boot_bus_req(cpu_req), .boot_bus_io(cpu_io), .boot_bus_we(cpu_we),
        .boot_bus_addr(cpu_addr), .boot_bus_wdata(cpu_wdata),
        .boot_bus_ready(cpu_ready), .boot_bus_rdata(cpu_rdata),
        .sd_blk_req(sd_req), .sd_blk_ready(server_ready), .sd_blk_lba(sd_lba),
        .sd_blk_we(sd_we), .sd_blk_tx_valid(sd_tx_valid), .sd_blk_tx_data(sd_tx_data),
        .sd_blk_rx_valid(bridge_rx_valid), .sd_blk_rx_data(sd_rx_data),
        .sd_blk_rx_ready(sd_rx_ready), .sd_blk_done(sd_done), .sd_blk_error(sd_error)
    );

    sd_spi_reader #(.INIT_HALF_CYCLES(16'd3), .DATA_HALF_CYCLES(16'd2),
        .INIT_RETRIES(13'd3), .TOKEN_WAIT_BYTES(24'd9),
        .CLIENT_WAIT_CYCLES(24'd25)) reader (
        .clk_sys(clk), .rst_n(rst_n), .sd_blk_req(server_req),
        .sd_blk_ready(sd_ready), .sd_blk_lba(sd_lba), .sd_blk_we(sd_we),
        .sd_blk_tx_valid(sd_tx_valid), .sd_blk_tx_data(sd_tx_data), .sd_blk_tx_ready(),
        .sd_blk_rx_valid(sd_rx_valid), .sd_blk_rx_data(sd_rx_data),
        .sd_blk_rx_ready(sd_rx_ready), .sd_blk_done(sd_done), .sd_blk_error(sd_error),
        .media_quiesce(server_quiesce), .sd_idle(sd_idle),
        .sd_cs_n(cs_n), .sd_sck(sck), .sd_mosi(mosi), .sd_miso(miso)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if (sd_we || sd_tx_valid || sd_tx_data !== 8'd0)
                $fatal(1, "Bridge issued a write");
            if (drop_final_byte && sd_done && (sd_error !== 4'd0 || streamed_bytes != 512))
                $fatal(1, "Short-stream fixture expected a successful full read from the card");
            if (server_req && sd_ready) begin
                accepts <= accepts + 1;
                streamed_bytes <= 0;
            end else if (sd_rx_valid && sd_rx_ready) begin
                streamed_bytes <= streamed_bytes + 1;
            end
        end
    end

    // SPI-mode SDHC fixture. Generate two sectors with distinct contents and
    // distinct halves. Fixed CRCs are from Python binascii.crc_hqx(bytes, 0).
    function [7:0] payload;
        input [31:0] addr;
        input integer index;
        begin
            payload = index[7:0] ^ {8{index[8]}} ^ (addr == FIRST_LBA ? 8'h6d : 8'ha3);
        end
    endfunction

    reg [47:0] command;
    reg [7:0] response [0:517];
    reg [15:0] crc;
    integer spi_bits, reply_bit, i;

    always @(negedge cs_n) begin
        spi_bits = 0;
        command = 0;
        for (i = 0; i < 518; i = i + 1)
            response[i] = 8'hff;
        miso = 1;
    end

    always @(posedge sck) begin
        if (!cs_n) begin
            spi_bits = spi_bits + 1;
            if (spi_bits <= 48)
                command = {command[46:0], mosi};
            if (spi_bits == 48) begin
                case (command[47:40])
                    8'h40: begin
                        cmd0_count = cmd0_count + 1;
                        response[1] = 1;
                    end
                    8'h48: begin
                        {response[1], response[2], response[3], response[4], response[5]} =
                            40'h01000001aa;
                    end
                    8'h77: response[1] = 1;
                    8'h69: response[1] = 0;
                    8'h7a: begin
                        {response[1], response[2], response[3], response[4], response[5]} =
                            40'h00c0ff8000;
                    end
                    8'h51: begin
                        if (command[39:8] !== expected_lba)
                            $fatal(1, "CMD17 expected LBA %08h, got %08h", expected_lba, command[39:8]);
                        cmd17_count = cmd17_count + 1;
                        response[1] = 0;
                        if (!omit_token) begin
                            response[3] = 8'hfe;
                            for (i = 0; i < 512; i = i + 1)
                                response[4+i] = payload(expected_lba, i);
                            crc = expected_lba == FIRST_LBA ? 16'h9059 : 16'h7105;
                            {response[516], response[517]} = crc ^ {15'd0, corrupt_crc};
                        end
                    end
                    default: $fatal(1, "Unexpected SPI command %h", command[47:40]);
                endcase
            end
        end
    end

    always @(negedge sck) begin
        reply_bit = spi_bits - 48;
        if (!cs_n && reply_bit >= 0 && reply_bit < 518*8)
            miso = response[reply_bit / 8][7 - (reply_bit % 8)];
        else
            miso = 1;
    end

    // Drive the same request-and-ready protocol as Ticket C. Keep the full
    // address and write data stable through the accepting fabric edge.
    task cpu_io_access;
        input [15:0] addr;
        input write_cycle;
        input [7:0] wdata;
        input integer expected_wait;
        output [7:0] rdata;
        integer waits;
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_we = write_cycle;
            cpu_wdata = wdata;
            cpu_req = 1;
            cpu_io = 1;
            @(posedge clk);
            waits = 0;
            while (!cpu_ready) begin
                if (addr[7:0] === DATA && (media_idle || cpu_rdata !== 8'hff))
                    $fatal(1, "DATA wait exposed a byte or reported idle");
                waits = waits + 1;
                @(posedge clk);
            end
            if (waits != expected_wait || (waits != 0 && media_idle))
                $fatal(1, "Port %04h wait cycles %0d, expected %0d", addr, waits, expected_wait);
            rdata = cpu_rdata;
            @(negedge clk);
            cpu_req = 0;
        end
    endtask

    task cpu_write;
        input [7:0] port;
        input [7:0] value;
        reg [7:0] ignored;
        begin
            cpu_io_access({value, port}, 1, value, 0, ignored);
        end
    endtask

    task expect_read;
        input [15:0] addr;
        input [7:0] expected;
        input integer expected_wait;
        reg [7:0] actual;
        begin
            cpu_io_access(addr, 0, 0, expected_wait, actual);
            if (actual !== expected)
                $fatal(1, "Read %04h expected %02h, got %02h", addr, expected, actual);
        end
    endtask

    task begin_read;
        input [31:0] addr;
        begin
            expected_lba = addr;
            cpu_write(LBA0, addr[7:0]);
            cpu_write(LBA1, addr[15:8]);
            cpu_write(LBA2, addr[23:16]);
            cpu_write(LBA3, addr[31:24]);
            expect_read({8'h89, LBA0}, addr[7:0], 0);
            expect_read({8'hbb, LBA3}, addr[31:24], 0);
            cpu_write(CONTROL, 1);
            expect_read({8'h00, CONTROL}, 8'h01, 0);
            expect_read({8'hab, DATA}, 8'hff, 0);
        end
    endtask

    task check_completion;
        input [7:0] expected;
        reg [7:0] status;
        begin
            status = 1;
            while (status[0])
                cpu_io_access({8'h00, CONTROL}, 0, 0, 0, status);
            if (status !== expected)
                $fatal(1, "Completion status expected %02h, got %02h", expected, status);
            expect_read({8'h00, CONTROL}, expected, 0);
        end
    endtask

    task check_sector;
        input [31:0] addr;
        integer offset;
        begin
            cpu_write(DATA, 8'hbe);
            // Cycle the high address byte as block I/O does with B.
            for (offset = 0; offset < 512; offset = offset + 1)
                expect_read({offset[7:0], DATA}, payload(addr, offset), 1);
            expect_read({8'h00, DATA}, 8'hff, 0);
            expect_read({8'h00, CONTROL}, 8'h02, 0);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        cpu_req = 1;
        cpu_addr = {8'h00, CONTROL};
        @(posedge clk);
        if (cpu_ready) $fatal(1, "Bridge claimed a memory request");
        @(negedge clk);
        cpu_io = 1;
        cpu_addr = 16'h00d6;
        @(posedge clk);
        if (cpu_ready) $fatal(1, "Bridge claimed an unrelated I/O port");
        @(negedge clk);
        cpu_req = 0;
        expect_read({8'h00, CONTROL}, 8'h00, 0);
        cpu_write(CONTROL, 8'hfe);

        begin_read(FIRST_LBA);
        wait (streamed_bytes == 512);
        expect_read({8'h00, CONTROL}, 8'h01, 0);
        expect_read({8'h00, DATA}, 8'hff, 0);
        check_completion(8'h06);
        check_sector(FIRST_LBA);

        // Leave an unread good sector before replacing it with a CRC failure.
        begin_read(FIRST_LBA);
        check_completion(8'h06);
        expect_read({8'h00, DATA}, payload(FIRST_LBA, 0), 1);
        corrupt_crc = 1;
        begin_read(RETRY_LBA);
        wait (streamed_bytes == 512);
        expect_read({8'h99, DATA}, 8'hff, 0);
        check_completion(8'h52);
        expect_read({8'h00, DATA}, 8'hff, 0);
        corrupt_crc = 0;
        begin_read(RETRY_LBA);
        check_completion(8'h06);
        check_sector(RETRY_LBA);
        if (cmd0_count != 2) $fatal(1, "CRC retry failed to reinitialize the card");

        // A successful completion with a short stream also leaves DATA invalid.
        drop_final_byte = 1;
        begin_read(FIRST_LBA);
        check_completion(8'h52);
        expect_read({8'h00, DATA}, 8'hff, 0);
        drop_final_byte = 0;

        // Queue work while the server cannot accept it, then start handoff.
        permit_command = 0;
        begin_read(FIRST_LBA);
        quiesce = 1;
        repeat (3) begin
            @(negedge clk);
            if (media_idle || !sd_req || sd_lba !== FIRST_LBA || accepts != 5)
                $fatal(1, "Queued command failed to hold through quiesce");
        end
        cpu_write(LBA0, 8'h5a);
        cpu_write(CONTROL, 1);
        expect_read({8'h00, LBA0}, FIRST_LBA[7:0], 0);
        permit_command = 1;
        wait (accepts == 6);
        @(negedge clk);
        if (media_idle || sd_req) $fatal(1, "Handoff lost the in-flight read");
        wait (streamed_bytes == 512);
        if (media_idle) $fatal(1, "Handoff drained before SD completion");
        check_completion(8'h06);
        if (!media_idle || !cs_n || sck) $fatal(1, "Handoff did not drain");
        cpu_write(CONTROL, 1);
        expect_read({8'h00, CONTROL}, 8'h06, 0);

        sd_owner_boot = 0;
        quiesce = 0;
        expect_read({8'h00, DATA}, 8'hff, 0);
        cpu_write(CONTROL, 1);
        sd_owner_boot = 1;
        expect_read({8'h00, CONTROL}, 8'h00, 0);
        expect_read({8'h00, DATA}, 8'hff, 0);
        if (accepts != 6 || cmd17_count != 6)
            $fatal(1, "Unexpected command count: accepts=%0d CMD17=%0d", accepts, cmd17_count);

        omit_token = 1;
        begin_read(FIRST_LBA);
        check_completion(8'h42);
        expect_read({8'h00, DATA}, 8'hff, 0);
        if (accepts != 7 || cmd17_count != 7 || streamed_bytes != 0)
            $fatal(1, "Token timeout did not retire one empty read");

        $display("PASS boot CPU to SD SPI: 512-byte sectors, CRC failure, retry, timeout, short stream, and ownership handoff");
        $finish;
    end
    initial #5000000 $fatal(1, "Watchdog expired");
endmodule
