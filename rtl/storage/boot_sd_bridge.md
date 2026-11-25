# Boot CPU SD bridge

`boot_sd_bridge` is the read-only `sd_blk_*` client for the Z80 loader. It
uses the [boot bus in §6](../../docs/contracts/interfaces.md#6-boot-and-diagnostics)
and the [block server in §5](../../docs/contracts/interfaces.md#5-media).
Route the boot bus from Ticket C during `boot_overlay`. The bridge asserts
`boot_bus_ready` only for its own I/O requests. Return its `boot_bus_rdata`
on that accepting edge and route memory and other I/O ports separately.

## Proposed loader I/O map

The shared contract leaves loader I/O addresses to Ticket E. This proposal
decodes the low byte and accepts every high byte. The Z80 can use immediate
I/O for the registers and two `INIR` instructions with `B=0` and `C=D5h`
for the sector stream. These ports are scoped to the boot overlay.

| Low byte | Read | Write |
|---|---|---|
| `D0h` | LBA bits 7:0 | Set LBA bits 7:0 |
| `D1h` | LBA bits 15:8 | Set LBA bits 15:8 |
| `D2h` | LBA bits 23:16 | Set LBA bits 23:16 |
| `D3h` | LBA bits 31:24 | Set LBA bits 31:24 |
| `D4h` | Status | Bit 0 starts a read. Other bits are ignored. |
| `D5h` | Next sector byte | Ignored |

Status bit 0 is busy, bit 1 is completion, bit 2 indicates unread data,
bit 3 is zero and bits 7:4 carry the block error code. Program the LBA and
write `01h` to `D4h` while idle. Poll for bit 1 with bit 0 clear, then test
the error field before reading 512 bytes from `D5h`. Completion and the
error field persist until a new start, loss of boot ownership or reset.
Busy covers both a queued command and an active SD transfer. LBA writes
and starts complete without effect while busy, quiesced or without boot
ownership. The LBA retains its value until written or reset.

A start immediately invalidates unread data from the previous sector and
clears the previous completion. Data becomes available at offset zero
only after 512 accepted bytes and a later successful `sd_blk_done`.
An error discards the buffered bytes and reports the server's error code.
A success pulse with a short stream reports I/O error 5. A valid `D5h`
read waits one fabric clock for RAM and advances the offset on the
`boot_bus_req && boot_bus_ready` edge. Early, failed or exhausted reads
return `FFh` immediately. The 512th read clears bit 2. Firmware can retry
with another start as soon as busy clears.

## Media ownership handoff

Assert `media_quiesce` at the bridge to stop new starts. A start already
accepted on the boot bus holds `sd_blk_req` and its LBA until the server
accepts it. The bridge then accepts the read stream and retires it on
`sd_blk_done`, even while quiesced. Keep the boot side selected in the SD
mux for the entire drain. While boot owns SD, qualify the SPI reader's
quiesce input with `boot_sd_idle` so a queued command can still reach the
server. In a boot/guest mux, the reader input is
`media_quiesce && (!sd_owner_boot || boot_sd_idle)` for a guest client
that stops submitting work when quiesced.

Keep the boot CPU bus connected until Ticket C reports `cpu_quiesced`.
Include both `boot_sd_idle` and the reader's `sd_idle` in the combined
`media_idle` before changing ownership. `boot_sd_idle` covers the queued
command, active transfer and any synchronous DATA reply. Unread buffered
bytes need no drain. Leaving boot ownership invalidates them and clears
the result. While boot lacks ownership, status reads zero and DATA reads
return `FFh`.

## Local checks and inferred RAM

The self-checking fixture uses a mock boot CPU, the bridge, the unmodified
SD SPI reader and a bit-level SDHC card model. It checks every byte of two
sectors, reads before and after CRC failure, retry of the failed LBA, a
missing-token timeout, a short stream with successful card completion,
and ownership handoff while a request is queued and then in flight.

```sh
verilator --lint-only -Wall --language 1364-2001 rtl/storage/boot_sd_bridge.v
iverilog -g2012 -s boot_sd_bridge_tb -o /tmp/boot_sd_bridge.vvp \
  rtl/storage/boot_sd_bridge.v rtl/storage/sd_spi_reader.v rtl/storage/tb/boot_sd_bridge_tb.v
vvp /tmp/boot_sd_bridge.vvp
yosys -p 'read_verilog rtl/storage/boot_sd_bridge.v; hierarchy -check -top boot_sd_bridge; proc; opt; memory -nomap; opt; check -assert; select -assert-count 1 t:$mem_v2; dump t:$mem_v2'
```

Yosys infers one 512 × 8 RAM (4,096 data bits) with one synchronous read
port and one synchronous write port at a shared address. One Cyclone I
M4K is expected. Quartus 11 fitting and board testing are pending.
