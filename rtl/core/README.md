# Ticket C Spectrum core

`core_subsystem` connects the pinned MiST T80pa to the Spectrum MMU,
ULA, guest I/O and boot bridge. The active descriptor comes from Ticket A.
The core uses the timing, paging, ROM mask, PSG, disk and input fields in
the [frozen interfaces](../../docs/contracts/interfaces.md).

## Integration

- Supply interleaved strobes from D in the `clk_sys` domain. The `ce_cpu`
  strobe coincides with every second `ce_ula` strobe and marks T80pa's
  positive half-cycle. The intervening `ce_ula` strobe marks its negative
  half-cycle. `psg_ce` passes the incoming `ce_psg` strobe to F during
  enabled guest operation.
- While `boot_overlay` is high, supply 48K-class enables and keep
  `guest_reset_n` low. Boot CPU accesses go through `boot_bus_*` to the
  adapter in E. The ULA continues drawing from the bank 5 mirror. Switch
  the overlay and active configuration with the CPU and guest held in
  reset. Release the guest after the clocks and SDRAM are ready.
- Assert `cpu_quiesce` to finish the current CPU bus access and stop at a
  bus boundary. Wait for `cpu_quiesced` and B's `mem_idle` before changing
  ownership. `cpu_quiesced` includes accepted read responses; B's
  `mem_idle` covers accepted write commits. Keep the boot adapter selected
  through completion of its final access.
- Wire `cpu_mem_*` and `screen_rd_*` to B. Guest reads issue on the first
  fabric edge after the CPU read strobe. At the proposed 85.90908 MHz
  fabric clock, three half-cycle intervals give at least 35 fabric clocks
  from request presentation to the earliest CPU data sample. A response on
  that edge bypasses the read register. A missing response or write accept
  at its deadline holds the corresponding CPU phase and sets the sticky
  `cpu_mem_deadline_miss` flag until fabric reset. Every such hold in guest
  operation is a memory integration failure.
- Sample raster signals on `ula_px_ce`. Coordinates start at the top-left
  visible border. Each bitmap/attribute pair is prefetched through B's
  synchronous read port, then rendered from byte registers. Floating-bus
  slots follow the guest timebase independently of those physical reads.
- The optional disk register interface is for Ticket G. `disk_req` is a
  one-edge pulse. For +3, `disk_reg` selects status (0) or data (1), and
  `disk_motor` comes from 1FFD. For Beta, indices 0–3 select the
  controller registers and index 4 selects the system port. Return
  combinational `disk_rdata` for reads. A validates controller availability
  before enabling a disk kind. Beta selects ROM slot 2 on M1 in 3Dxx
  while ROM 1 is active, and releases it on M1 in RAM.

## Timing profiles

| Timing ID | Model | T-states per line | Lines per frame | INT width in T-states |
|---|---|---:|---:|---:|
| 0 | Sinclair 16/48K PAL | 224 | 312 | 32 |
| 1 | Sinclair 128K and grey +2 | 228 | 311 | 36 |
| 2 | +2A/+3 | 228 | 311 | 32 |
| 3 | TK90X 50 Hz | 228 | 312 | 32 |
| 4 | TK90X 60 Hz | 228 | 262 | 32 |
| 5 | Pentagon 128 | 224 | 320 | 36 |

The Sinclair contention tests use early timing. The first pattern entries
occur 14,335 T-states after INT for 16/48K and 14,361 for 128K and the
Amstrad ASIC. The latter uses its own delay table and leaves I/O cycles
uncontended. The ULA receives the resolved physical RAM bank, including the
four ASIC all-RAM layouts. [Fuse contention tables](https://github.com/fuse-emulator/fuse/blob/master/spectrum.c)
and [frame timings](https://github.com/fuse-emulator/libspectrum/blob/master/timings.c).

TK uses the Microdigital horizontal sync and 50/60 Hz vertical timing.
The FE model assumes the stock Brazilian TK90X D1 diode, so FE bit 7 is
low. F supplies the normalized EAR level. [TK90X ULA measurements and schematics](https://www.victortrucco.com/TK/DissecandoULA/DissecandoULA)
and [TK90X FE measurements](https://cantinhotk90x.blogspot.com/2012/11/rom-e-porta-254-parte-1.html).

## Build and checks

For Quartus, analyze `T80_Pack.vhd`, `T80_ALU.vhd`, `T80_MCode.vhd` and
`T80_Reg.vhd` from the pinned `vendor/ZX_Spectrum-128K_MIST/T80/` tree.
Then analyze this directory's adapted `T80.vhd`, the donor's `T80pa.vhd`
and this directory's `spectrum_cpu.vhd` in that order. Add the four Verilog
files in this directory to the same design. The [vendor inventory](../../docs/VENDOR_INVENTORY.md)
records the revisions and T80 redistribution terms.

Run `rtl/core/tb/run_checks.sh` from the worktree. It checks the
handwritten RTL with Verilator's Verilog-2001 mode, runs the CPU program
with native VHDL-93 and translated CPU implementations, and checks the
integrated core with Yosys. It then runs the synthetic CPU/MMU/I/O fixture,
full-frame ULA checks and a stress test with B's real controller and D's
clock enables. All fixtures are ROM-free. The Yosys gate checks for zero
combinational loops, latch cells and inferred RAMs. Build products and logs
go to a temporary directory.

The local translation uses the same adapted T80 as Quartus. The native
smoke program compares its bus trace with the pinned donor's trace.
`block_io_parity_tb` compares the production parity function against the
donor's masked sum across all 32,768 relevant binary input combinations.

Full-system qualification still includes the Quartus 11.0 SP1 fit and STA,
hardware checks for CPU/video and EAR phase, instruction-internal
contention without external bus strobes, and integration with the actual
boot, audio and disk backends.
