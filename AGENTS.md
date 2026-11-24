# AGENTS.md — TRHMSX ZX Spectrum Port (Cyclone I / EP1C12)

Read `docs/TRHMSX-Spectrum-Port.md` before designing or modifying any subsystem. That file is the authoritative engineering spec.

## Target Platform & Hard Limits
- **Board:** TRHMSX v1.51 production netlist/BOM/schematic (`cristianoag/trhmsx` @ `f330fe7`). Never use `hardware/_old/1.4`.
- **FPGA:** Altera Cyclone I `EP1C12Q240C8N` — **12,060 LEs, 52 M4K blocks, 239,616 total RAM bits (including parity), 2 PLLs**.
- **Board hardware:** 21.47727 MHz crystal, `MT48LC16M16A2TG` x16 SDR SDRAM (**stay within the lower 4 MiB byte ceiling** until physical address lines are verified), `EPCS4` flash on Active Serial header J8 (NOT JTAG), no EAR input on stock J11.
- **Compiler:** Quartus II 11.0 SP1 Web Edition (runs on separate Windows XP build box). Local verification on Linux uses `iverilog`, `verilator`, `ghdl`, and `yosys`.
- **Primary donor:** `sorgelig/ZX_Spectrum-128K_MIST` @ `9713924` (recursive, with `mist-devel/T80` @ `0e89c18`). Start with `T80pa`, ULA, and paging; defer `u765`/WD1793 disk controllers until after the base fit.

## Non-Negotiable Constraints (Do Not Violate)
1. **Never import the MiST `.qsf`** (targets EP3C25 / 27 MHz) and **never reuse `vram.v`** (32768x8 = 262,144 bits > entire EP1C12). Mirror only offsets `0..6911` of physical screen banks 5 and 7 (addressed by *physical* bank, updated by all RAM writers).
2. **Quartus 11.0 SP1 compatibility:** Keep synthesis RTL conservative. Avoid SystemVerilog constructs known to break Quartus 11 (`ym2149.sv` array aggregate resets, inferred multidimensional memories in `u765.sv`, `.*` port wildcards). Only rewrite constructs rejected by Quartus 11, and prove identical simulation traces before/after.
3. **Mixed-language rule:** `T80` is VHDL. A Verilog-only lint pass does NOT validate CPU integration. Use `ghdl` (or a documented VHDL-to-Verilog synthesis step via `ghdl` + `yosys`) alongside Verilog simulation.
4. **Known donor ULA bug:** `ula.sv`'s `contendAddr` does not handle +2A/+3 banks 4–7 or all-RAM modes. Pass resolved physical bank + explicit contention profile into the ULA.
5. **External SDRAM byte map (frozen contract):**
   - `000000–01FFFF` Guest RAM (8 x 16 KiB banks)
   - `020000–02FFFF` Active ROM (4 banks)
   - `030000–03FFFF` Staging ROM
   - `040000–07FFFF` Loader workspace / media metadata
   - `080000–0FFFFF` Optional media cache
6. **Licensing & ROM hygiene:** Keep upstream unmodified code in `vendor/` with a commit/license inventory (`GPLv2` for MiST; OCM-PLD is noncommercial—derive `boards/trhmsx_v151/` wrappers strictly from electrical facts, never copy OCM RTL). Never commit copyrighted/third-party Spectrum ROM images to this repo.
7. **Electrical safety:** Keep cartridge slots and ESP8266 pins idle/released. Never reuse OCM's EPBIOS flash offset in Spectrum `.pof` generation.

## Repository Layout & Ticket Ownership
Edit ONLY files inside your assigned ticket directory. Only Ticket A (Integration) may modify top-level wiring, `.qsf`/`.qpf`, shared contracts, or `boards/`.
- `docs/` — Engineering specs & frozen interface contracts
- `vendor/` — Pinned upstream donor trees (read-only)
- `boards/trhmsx_v151/` — **Ticket A:** Quartus 11.0 SP1 project, top module, `pins.csv`, PLLs, constraints, integration
- `rtl/memory/` — **Ticket B:** x16 SDRAM controller, DQM byte lanes, loader arbitration, screen mirror snoop
- `rtl/machine/` — **Ticket C:** T80pa integration, FE port, ULA, 16/48/128/+2/+2A/+3/TK/Pentagon MMU & contention
- `rtl/video/` — **Ticket D:** Clock enables, line-doubled VGA (6-bit RGB), optional 60 Hz LCD framebuffer
- `rtl/storage/` & `firmware/` — **Ticket E:** SPI SD controller, Z80 boot loader, FAT16/32 reader, ROM/media staging
- `rtl/io/` & `rtl/audio/` — **Ticket F:** PS/2 Set 2 decoder, dual DE-9 joysticks, AY-3-8912 wrapper, beeper/MIC mixer
- `rtl/media/` — **Ticket G:** TAP pulse player, `u765` (DSK), `wd1793`/Beta (TRD)
- `tests/` & `results/` — **Ticket H:** Independent goldens, ROM-free fixtures, regression scripts, per-commit evidence tables

## Verification & Definition of Done
- **No circular tests:** Never generate a golden trace from the RTL being tested. Derive goldens from specs, Fuse (where models match), or published timing tests.
- **No fabricated evidence:** Track `Simulated`, `Quartus Fitted`, and `Board Tested` as separate columns in `results/`. Never mark a feature fitted or board-tested without archived reports/measurements.
- **Local checks before finishing any task:**
  - Verilog/SV lint: `verilator --lint-only -Wall <files>`
  - Verilog sim: `iverilog -g2012 -o /tmp/sim.vvp <tb_and_rtl> && vvp /tmp/sim.vvp`
  - VHDL check/sim (for T80): `ghdl -a --std=93 <vhdl_files>`
- Run `git status` and `git diff --stat` before finishing to confirm no out-of-scope files were modified.
