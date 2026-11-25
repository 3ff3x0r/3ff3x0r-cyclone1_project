# Read-only SD SPI block server

The first part of Ticket E implements the physical single-sector interface
in docs/contracts/interfaces.md §5. It uses the SD Association Physical Layer
Simplified Specification as its protocol reference.

The first read after reset initializes the card. CMD8-capable cards and
legacy SDSC cards use CMD55/ACMD41, followed by CMD58. SDSC uses CMD16 and
byte addressing. SDHC/SDXC uses block addressing. The server reads one
sector with CMD17 and checks the two CRC16 bytes before reporting success.
The client must discard all bytes from a transaction that finishes with
an error. Writes complete with error 3 and leave the card untouched.

The server pauses SCK between bytes under backpressure. It times out a
stalled client, an unresponsive command and a missing data token. A
communication failure invalidates initialization, so the next read retries
it. Pulse reset while idle to force reinitialization following an explicit
card swap. There is no hardware card-detect input. Media quiesce prevents new
accepts while any accepted command drains. Use sd_idle for the ownership
handoff.

The dividers assume 85.909 MHz and give about 398 kHz during initialization
and 10.74 MHz after initialization. If changing the fabric rate, recalculate
the dividers and timeout counts together. The 512 deselected startup clocks
must also allow at least 1 ms after supply stabilization. Tie the write
stream inputs low for read-only clients.

Board wiring belongs to Ticket A. Match the existing board pin names
sd_cs_n, sd_sck, sd_mosi and sd_miso. The SPI engine uses mode 0, with SCK
low while idle. Review generated SCK and MISO timing on the fitted build.
A CPU bridge, physical board diagnostic, FAT, ROM selection and disk-image
services follow this slice.

Run the standalone regression from the repository root.

```sh
verilator --lint-only -Wall --language 1364-2001 rtl/storage/sd_spi_reader.v
iverilog -g2012 -s sd_spi_reader_tb -o /tmp/sd_spi_reader.vvp \
  rtl/storage/sd_spi_reader.v rtl/storage/tb/sd_spi_reader_tb.v
vvp /tmp/sd_spi_reader.vvp
yosys -p 'read_verilog rtl/storage/sd_spi_reader.v; hierarchy -check -top sd_spi_reader; proc; opt; check -assert; stat'
```
