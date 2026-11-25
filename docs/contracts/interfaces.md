# TRHMSX Spectrum integration contracts

Frozen for Tickets B–H. The names, encodings and edge rules below implement
[Section 4 of the port handoff](../TRHMSX-Spectrum-Port.md#4-contracts-to-freeze-before-parallel-work).
Use Verilog-2001 or VHDL-93 ports. Widths are in bits and vectors use
`[width-1:0]`. Directions are shown as producer → consumer.

## Common clock and reset rules

- Sample on rising `clk_sys` unless a table specifies `clk_vga`. All asserted
  controls are high except names ending in `_n`, which are active low.
- `rst_n` and `rst_vga_n` assert asynchronously and release synchronously
  to their own clock. A qualifies their release with clock lock. CDC logic,
  SDRAM initialization and physical pin control belong to the receiving
  subsystem and the board wrapper. A `guest_reset_n` assertion leaves fabric,
  SDRAM, physical input state, mounted media and the active configuration live.
- `valid && ready` transfers on a rising edge. The producer holds valid and
  payload stable while waiting. Consecutive qualifying edges are consecutive
  transfers. A signal called a pulse is high for one full clock cycle and is
  observed on one rising edge. An idle producer drives request, valid and
  write strobes low. Consumers sample payload only on qualifying edges.

## 1. Machine configuration

E presents the following proposed fields as `pending_*`. A exposes the
latched copy as `cfg_*` to C, D, F and G. Each field in the table expands to
two ports with the indicated prefixes and width. E holds all pending fields
from commit request until `boot_commit_done`. The active copy changes together
on one `clk_sys` edge while the guest is held in reset, after the ROM
promotion and required RAM initialization complete.

| Field | Width | Encoding |
|---|---:|---|
| `profile_id` | 4 | 0 diagnostic, 1 Sinclair 16K, 2 Sinclair 48K PAL, 3 Sinclair 128K, 4 grey +2, 5 +2A, 6 +3, 7 TK90X, 8 Pentagon 128. Others reserved. |
| `ram_size_id` | 2 | 0 = 16 KiB, 1 = 48 KiB, 2 = 128 KiB. 3 reserved. |
| `timing_id` | 3 | 0 Sinclair 48K PAL, 1 Sinclair 128K PAL, 2 +2A/+3 PAL, 3 TK90X 50 Hz, 4 TK90X 60 Hz, 5 Pentagon 128. Others reserved. |
| `paging_id` | 3 | 0 fixed 16K, 1 fixed 48K, 2 Sinclair 128K/grey +2, 3 +2A/+3, 4 Pentagon 128. Others reserved. |
| `rom_set_id` | 16 | Manifest identifier. 0 reserved for the built-in diagnostic. |
| `rom_valid_mask` | 4 | Bit i qualifies logical ROM slot i. Manifest lists slots explicitly. |
| `psg_enable` | 1 | 1 enables AY port decoding and sound. 0 disables both. |
| `disk_kind` | 2 | 0 none, 1 +3 DSK/uPD765, 2 Pentagon TRD/Beta, 3 reserved. |
| `input_map_id` | 2 | 0 dual Sinclair Interface 2, 1 P1 Kempston plus P2 Sinclair, 2 keyboard only, 3 reserved. |
| `joy1_b_map`, `joy2_b_map` | 2 each | 0 disabled, 1 SPACE, 2 SYMBOL SHIFT, 3 extended Kempston bit 5 for P1 in mapping 1. Reject 3 for P2 or other mappings. |

A resets the active descriptor to profile 0, with every field zero, and
`cfg_valid=0` (1 bit, A → C/D/F/G). That selects the built-in boot/diagnostic
environment. A sets `cfg_valid=1` with the atomic latch. E and A validate
reserved values and profile combinations before promotion. Base combinations
are 16K/48K fixed with one ROM and timing 0, 128K/+2 with 128 KiB, two ROMs
and timing 1, and +2A/+3 with 128 KiB, four ROMs and timing 2. TK90X uses
its declared 16K/48K fixed map with one ROM and timing 3 or 4. Pentagon uses
128 KiB and timing 5, with two CPU ROMs and slot 2 for TR-DOS when Beta is
enabled. Disk kind 1 is available to +3, and kind 2 to Pentagon with slot 2
present. An absent optional controller must be rejected as unsupported.
The diagnostic uses a 48K-class raster and fixed 16K defaults. Guest reset
clears CPU/MMU state, including the paging lock, and preserves `cfg_*` and
the active ROM contents. ROM identity and profile remain separate.

## 2. Memory

B serves two byte clients in `clk_sys`. Each table row expands to a
`cpu_mem_*` port (C or the boot CPU bus adapter ↔ B through A) and a
`ld_mem_*` port (loader/media/promotion arbiter ↔ B). A connects the CPU
guest decoder or boot bus adapter according to the boot overlay ownership.

| Field | Width | Direction | Meaning |
|---|---:|---|---|
| `req` | 1 | client → B | Transaction pending |
| `accept` | 1 | B → client | Ready to capture the request |
| `addr` | 22 | client → B | Physical byte address |
| `we` | 1 | client → B | 1 write, 0 read |
| `wdata` | 8 | client → B | Byte to write |
| `rvalid` | 1 | B → client | Read response pulse |
| `rdata` | 8 | B → client | Read response byte when `rvalid=1` |

- `req && accept` enqueues exactly one read or write. Each client may have
  one read outstanding and issues no new request until its one-cycle
  `rvalid` has been sampled. The earliest response is the next edge after
  acceptance. Read results are consumed unconditionally. Writes have no
  response and commit exactly once. B preserves acceptance order per client
  and read-after-write visibility for overlapping bytes across clients.
  If B accepts both clients on one edge, CPU precedes loader for ordering.
- `mem_ready` (1, B → A/clients) indicates completed SDRAM initialization.
  `mem_idle` (1, B → A) means no accepted user transaction, pending read
  response or write commit remains. Periodic refresh may run while idle.
  A inhibits new requests and drains accepted work before changing ownership.
  Guest reset alone neither cancels accepted writes nor resets B.
- B must reserve guest service through refresh and loader traffic. C presents
  translated reads early enough for the model's CPU sample edge. A, B, C and
  H use the profile bus schedule and worst-case refresh alignment to verify
  that deadline, including adjacent reads and writes. A memory miss at the
  sample edge is an integration failure. Normal-operation stalls are limited
  to model-defined contention. The boot adapter may wait for SDRAM.
- C resolves ROM/RAM and physical bank on every access. Guest ROM writes and
  unmapped accesses terminate in C with profile-specific behavior. The loader
  CPU adapter maps `4000–5FFF` to physical bank 5 at
  `014000–015FFF` when `boot_overlay=1` (§6). The loader/media arbiter
  bounds every DMA against its assigned region before raising `req`.
  Fixed 16K maps bank 5 at CPU `4000–7FFF`. Fixed 48K maps banks
  5, 2 and 0 in ascending RAM windows. Paged profiles resolve each
  window before issuing the request, including the four +2A/+3 all-RAM
  layouts in Section 5 of the handoff.
- The fabric presents a 22-bit byte address `a`. On the x16 bus,
  `a[0]=0` selects DQ[7:0] with DQM[0] low and DQM[1] high for a
  byte write. `a[0]=1` selects DQ[15:8] with the masks reversed.
  B uses the same lane selection on reads. B owns physical row, column
  and bank-address mapping, including any bank interleaving, based on the
  geometry verified on the fitted U5. Release DQ, deselect commands and
  mask both lanes while held in reset. Pad timing and the SDRAM phase
  clock are internal to B.

### Screen mirror and contention

| Ports | Width | Direction | Meaning |
|---|---:|---|---|
| `screen_rd_req`, `screen_rd_bank7`, `screen_rd_offset` | 1, 1, 13 | C → B | One synchronous read per edge. 0 selects physical bank 5, 1 selects bank 7. Offset 0–6911. |
| `screen_rd_valid`, `screen_rd_data` | 1, 8 | B → C | Registered after the edge following request capture, for consumption two `clk_sys` edges after capture. No backpressure. |
| `ula_bus_valid`, `ula_bus_is_ram`, `ula_bus_ram_bank`, `ula_contend_id` | 1, 1, 3, 3 | C MMU → C ULA | Qualify the resolved physical RAM bank for the current bus cycle. Profile IDs below. |

Every committed write from either client to RAM bank 5 or 7 at offsets
0–6911 updates its mirror on the same commit edge. Other writes leave the
mirror alone. A simultaneous mirror read and same-byte commit returns
the new byte with explicit forwarding. Both mirror ports are synchronous.
The loader clears bank 5 before its first screen use. In boot mode, C
renders from its mirror using `screen_rd_bank7=0`, with the boot raster
enabled while guest peripherals are held in reset. CPU writes at
`4000–5AFF` update that mirror through the same commit path. Initialize
the mirror bytes for both banks before the first guest read.
ULA contention IDs are 0 none, 1 Sinclair 16/48, 2 128/+2,
3 +2A/+3, 4 TK 50 Hz and 5 TK 60 Hz. Sinclair 16/48 contends with
physical bank 5, 128/+2 with odd banks and +2A/+3 with banks 4–7.
Pentagon uses 0. C applies the ID to phase, I/O decoding and floating-bus
behavior independently of RAM membership. An unmapped access sets
`ula_bus_is_ram=0`.

### External SDRAM byte map

All ranges are inclusive and addresses are hexadecimal. RAM bank numbers
and ROM slots are zero-based and 16 KiB each.

| Physical byte range | Allocation and access |
|---|---|
| `000000–01FFFF` | Guest RAM. Bank i starts at `i << 14`. C maps only the banks populated by the profile. |
| `020000–02FFFF` | Active ROM. Slot i starts at `020000 + (i << 14)`. Guest read-only. Only boot promotion writes here. |
| `030000–03FFFF` | Staging ROM. Same slot offsets as active ROM. Loader writes and validates here before promotion. |
| `040000–07FFFF` | Loader workspace and media metadata. |
| `080000–0FFFFF` | Optional media cache and staged TAP/disk bytes. |
| `100000–3FFFFF` | Unallocated within the lower 4 MiB validation ceiling. Bench diagnostics may test this range under exclusive ownership. |
| `400000` and above | Outside the ceiling. Reject before address narrowing. |

The map is private to the fabric. The on-chip boot ROM occupies a reset
overlay in the CPU address space. Validate DMA start and span using widened
arithmetic before submitting bytes. In particular, length from a media file
cannot authorize writes into another region. U5's BOM describes 32 MiB
nominal capacity. This release uses a 4 MiB ceiling pending physical alias
and address-line tests. [Micron SDRAM data sheet](https://media.digikey.com/PDF/Data%20Sheets/Micron%20Technology%20Inc%20PDFs/MT48LC64M4A2%2C32M8A2%2C16M16A2.pdf)

## 3. Video and model enables

| Ports | Width | Direction | Meaning |
|---|---:|---|---|
| `ce_cpu`, `ce_ula`, `ce_psg` | 1 each | D → C/F/G | One `clk_sys` tick per enabled model step. CPU is the base T-state cadence before contention. ULA runs at two pixel ticks per T-state and PSG at half CPU base cadence when enabled. |
| `ula_px_ce` | 1 | C → D | Sample all ULA raster signals on this edge. |
| `ula_color` | 4 | C → D | `[3:0]` = bright, G, R, B. Black remains black with either brightness. |
| `ula_x`, `ula_y` | 10, 9 | C → D | Raster coordinates in guest pixels and lines from the profile's frame origin. Include border and blanking. |
| `ula_hs_n`, `ula_vs_n` | 1 each | C → D | Separate active-low guest sync. |
| `ula_blank` | 1 | C → D | 1 blanks the pixel. Visible border uses 0. |
| `clk_vga`, `rst_vga_n` | 1 each | A/D → board scanout | Output pixel clock and its reset. |
| `vga_r`, `vga_g`, `vga_b` | 6 each | D → A | Unsigned DAC codes in `clk_vga`, MSB is bit 5. Drive zero in blanking and reset. |
| `vga_hs_n`, `vga_vs_n`, `vga_blank` | 1 each | D → A | Separate active-low scanout syncs and active-high blanking. Syncs idle high. `vga_blank` is internal. |

`ula_x=0` denotes the first tick of each line and `ula_x=ula_y=0`
the first tick of a frame. Normal coordinate progression includes blanking.
D derives a deterministic phase relationship for the three enables. C applies
bus contention without slowing ULA, PSG or the tape timebase. D owns CDC
buffering and consumes every qualified raster sample without backpressure.
The primary scanout doubles every guest line at the guest frame rate.
D can offer an independent LCD scanout using completed-frame swaps and
whole-frame repetition. Its output timing stays independent of emulation.
Line/porch/sync counts and actual PLL rates follow the selected model and
display mode and are measured by D/H.

## 4. Input and audio

| Ports | Width | Direction | Meaning |
|---|---:|---|---|
| `key_matrix_n` | 40 | F → C/E | Held keyboard matrix in `clk_sys`. 0 is pressed and all ones is idle. |
| `joy1`, `joy2` | 6 each | F → C/E | Active-high pressed state. Bits 0–5 are up, down, left, right, A, B. All zero is idle. |
| `recovery_key` | 1 | F → A | Held physical PS/2 Set 2 F12, independent of guest key mapping. |
| `soft_reset_key` | 1 | F → A | Held physical PS/2 Set 2 F11 for a soft guest reset. |
| `ear_bit` | 1 | F → C | Normalized FE bit 6 after source selection and profile-specific idle. |
| `tap_play_toggle`, `tap_rewind` | 1 each | F → G | One-cycle pulses on fresh F9 and F10 presses respectively. |
| `tap_playing` | 1 | G → F | High while playback runs. |
| `tap_ear_valid`, `tap_ear_bit` | 1 each | G → F | While valid, TAP supplies the EAR level. The level is held between pulse transitions. |
| `mic_bit`, `beeper_bit` | 1 each | C → F | Held FE output bits 3 and 4 respectively. Reset to 0. |
| `ay_req`, `ay_op`, `ay_wdata` | 1, 2, 8 | C → F | One decoded AY bus pulse. Operation 0 = register select, 1 = data write, 2 = selected-register read, 3 reserved. |
| `ay_rdata` | 8 | F → C | Combinational selected-register readback during the read cycle. No wait handshake. |
| `psg_a`, `psg_b`, `psg_c` | 8 each | C-facing AY core in F → F mixer | Unsigned levels held between PSG enables. Disabled/reset levels are zero. |
| `audio_l`, `audio_r` | 6 each | F → A | Final unsigned DAC codes, held between mixer updates. Reset code 0. |
| `mic_record` | 1 | E/A → F | 1 routes clean MIC to the left DAC. Right DAC retains the normal mix. Changes take effect on a mixer update. |

Matrix bit `5*r+c` is row `r`, column `c`, counted from zero. Rows in
A8–A15 order, and columns in FE bit 0–4 order, are
`CAPS SHIFT,Z,X,C,V`, `A,S,D,F,G`, `Q,W,E,R,T`, `1,2,3,4,5`,
`0,9,8,7,6`, `P,O,I,U,Y`, `ENTER,L,K,J,H`, `SPACE,SYMBOL SHIFT,M,N,B`.
C ANDs every row selected by a low address bit and returns ones if none is
selected. For mapping 0, P1 left/right/down/up/A maps to 6/7/8/9/0 and P2
to 1/2/3/4/5. Mapping 1 keeps P2 on 1/2/3/4/5 and maps P1 Kempston bits
0–4 to right/left/down/up/A. C ORs positive keyboard and joystick press
sources before active-low FE encoding. A release in one source leaves
other held sources active.

F9–F12 are reserved host controls and stay out of the Spectrum matrix.
F suppresses typematic repeats. For TAP it emits a pulse on the first
make after release. For reset it reports the held levels to A (§6).

C owns profile-specific AY and FE address decoding. F owns the AY-3-8912
registers, samples and audio mixing. F chooses TAP EAR while valid, otherwise
the profile idle level on the stock board. The board wrapper is the sole
owner of physical pads. The logical input/audio ports can be tested with
fixtures independently of the PS/2 electrical hold below.

## 5. Media

E provides the physical SD block server (`sd_blk_*`) and the file-relative
image server (`img_blk_*`) to G. E's FAT/mount code uses the physical
server via a bridge. During guest ownership only E's image backend can
submit physical requests, and G consumes file-relative blocks. These
interfaces carry single-sector transactions. Each field expands to both
port prefixes except where stated.

| Field | Width | Direction | Meaning |
|---|---:|---|---|
| `req`, `ready` | 1 each | client → server, server → client | Command acceptance on `req && ready` |
| `lba` (SD), `block` (image) | 32 | client → server | Card LBA or zero-based file-relative 512-byte block |
| `we` | 1 | client → server | 1 write, 0 read |
| `tx_valid`, `tx_data`, `tx_ready` | 1, 8, 1 | client → server, client → server, server → client | Client streams write bytes |
| `rx_valid`, `rx_data`, `rx_ready` | 1, 8, 1 | server → client, server → client, client → server | Server streams read bytes |
| `done`, `error` | 1, 4 | server → client | Unconditional completion pulse with status |

Only one transaction is outstanding per server. Byte streams start on a
later edge than command acceptance, run in ascending offset order 0–511,
and transfer only on valid/ready. The other direction is idle. Completion
is observed on a later edge than the final transfer for success and may
arrive early on failure. A client discards partial read data on error.
Receivers use timeout or abort handling so card removal and stalled
physical commands complete with an error. Error codes are 0 success,
1 no card/not mounted, 2 out of range, 3 write protected, 4 timeout,
5 I/O or SD protocol failure, 6 malformed map/unsupported, 7 aborted.
Codes 8–15 are reserved. Errors retire the transaction. Write success
means the selected backend has accepted all 512 bytes, including card
completion for a direct write. A deferred-write backend marks its
modified block dirty before success. A failed physical write can leave
the target block uncertain, and error handling must preserve the dirty
state and report failure.

| Ports | Width | Direction | Meaning |
|---|---:|---|---|
| `img_mounted`, `img_length`, `img_readonly` | 1, 32, 1 | E → G | Active disk mount descriptor. Length is in bytes. Reset is unmounted, length 0, read-only. |
| `tap_mounted`, `tap_base`, `tap_length` | 1, 22, 32 | E → G | Staged TAP span inside the media cache. Mount validated before guest ownership. |
| `tap_mount_update` | 1 | E → G | One-cycle descriptor update, including remounts with the same base and length. Sample all three descriptor fields on this edge. |
| `tap_rd_req`, `tap_rd_accept`, `tap_rd_offset`, `tap_rd_valid`, `tap_rd_data` | 1, 1, 32, 1, 8 | G → E, E → G, G → E, E → G, E → G | File-relative read-only TAP adapter with the memory boundary's acceptance and response rules. G issues offsets below length, and E grants acceptance only for a valid mounted range. E maps accepted requests to the loader/media RAM arbiter. |
| `media_quiesce` | 1 | A → E/G | Stop initiating new transactions and retire work already accepted. |
| `media_idle` | 1 | E/G → A | Combined idle indication. No SD, image or TAP request or response remains outstanding. |

E may publish mount descriptor changes only while the affected client is
quiescent and requests are gated. A holds guest execution during this
transition. G captures TAP descriptor updates in the fabric reset domain
so a publish edge can arrive while `guest_reset_n` is low. Guest reset
preserves mount descriptors and dirty state.
Reject an image block if its full 512-byte span crosses file length.
Check the span before shifting or narrowing, even when the file fits in
cache. A live image backend maps the validated file offset through the
FAT cluster chain or a validated extent table before submitting a card
LBA. Staged read-only images may serve from cache directly. A writable
backend bounds writes to the existing file and refuses eviction of dirty
data until flush succeeds or the user explicitly discards it. TAP is
byte-addressed and can play a file with a partial last sector. G prefetches
from staging to keep pulse timing independent of filesystem traffic.

G starts paused at offset zero on mount or guest reset. During guest
operation, `tap_play_toggle` starts or resumes a mounted TAP, or pauses
it and holds the byte position and pulse phase. `tap_rewind` discards
prefetched data and returns to offset zero, paused. Reset and mount
updates take priority over rewind, and rewind takes priority over toggle.
Ignore transport pulses while unmounted, quiescing, or in the boot
overlay. Retire any accepted read before reusing its request slot and
discard stale responses after a rewind. At EOF playback stops until
rewound. While paused, at EOF, or during startup prefetch, G deasserts
`tap_ear_valid` and F supplies the profile's idle EAR level. Start the
guest's `LOAD ""` before pressing F9.

## 6. Boot and diagnostics

| Ports | Width | Direction | Meaning |
|---|---:|---|---|
| `clocks_ready`, `mem_ready`, `mem_idle` | 1 each | D/A, B, B → A/E | Qualified guest clock enables, initialized SDRAM, and transaction drain status. |
| `boot_overlay`, `sd_owner_boot` | 1 each | A → C/E/G | 1 selects loader address decode and grants E's boot path exclusive card ownership respectively. Both reset high. |
| `cpu_reset_n`, `guest_reset_n` | 1 each | A → C, C/F/G | CPU reset and guest peripheral reset. Both assert low, with synchronous release. |
| `board_reset_n` | 1 | U1-153 → A | Active-low cold-reset input driven by U6-6. SW2 actuates U6. |
| `soft_reset_key`, `recovery_key` | 1 each | F → A | Held F11 and F12 respectively. A detects rising edges during guest operation. |
| `boot_recovery` | 1 | A → E | Latched loader recovery selection. |
| `boot_commit_valid`, `boot_commit_ready` | 1 each | E → A, A → E | One-shot commit command, with pending descriptor from §1. |
| `boot_stage_ok`, `boot_ram_init_ok` | 1 each | E → A | Sampled with commit acceptance. Both are required for success. Qualify validated exact ROM lengths, slot order and CRC, and completed RAM initialization including physical bank 5. |
| `boot_publish` | 1 | A → E | One-cycle enable to publish the pending mount descriptors on the same edge as the configuration latch. |
| `boot_commit_done`, `boot_error` | 1, 8 | A → E | Completion pulse and status. A retains the error code until a new attempt or reset so the loader can render it. |
| `loader_diag_active`, `loader_diag_code` | 1, 8 | E → A/D | Held diagnostic status and visible code for firmware failures, including when no commit was attempted. |
| `boot_bus_req`, `boot_bus_io`, `boot_bus_we` | 1 each | C → E through A | CPU access pending, 1 I/O vs 0 memory, 1 write vs 0 read. Qualified only with the boot overlay. |
| `boot_bus_addr`, `boot_bus_wdata` | 16, 8 | C → E through A | Full CPU byte address or I/O port number and write data. |
| `boot_bus_ready`, `boot_bus_rdata` | 1, 8 | E → C through A | Access completes on `req && ready`. Read data is valid on that edge. |

The boot bridge holds `boot_bus_req` and its payload through completion.
It issues one request per CPU access and may stall boot CPU execution
while waiting. While `boot_overlay=1`, decode these inclusive byte ranges.

| CPU range | Boot mapping |
|---|---|
| `0000–0FFF` | 4 KiB on-chip boot ROM. Ignore writes. |
| `4000–5FFF` | First 8 KiB of physical RAM bank 5 at fabric `014000–015FFF`. `4000–5AFF` is the mirrored screen. |
| `6000–FFFF` | Loader RAM at fabric `040000–049FFF`. |

Unmapped memory reads return `FF`. If FAT16/32 and the menu exceed
4 KiB, the boot ROM may act as stage 1, load a stage-2 menu binary from SD
into loader RAM, and transfer execution there with the overlay still
active. Loader I/O registers and any banked staging access through them
are internal to E. The boot adapter passes only bounded fabric accesses
to B. No guest bus cycle reaches these loader registers.

E clears and initializes physical bank 5 before setting
`boot_ram_init_ok`. The CPU screen window covers its first 8 KiB.
Use the loader memory port to initialize the rest of bank 5
(`016000–017FFF`) and wait for all initialization writes to commit
before asserting the flag.

On fabric reset A selects the boot overlay and holds guest peripherals in
reset. A releases the CPU into on-chip boot ROM at address zero once
clocks are ready. The boot CPU gates SDRAM activity on `mem_ready`.
The loader offers a recovery window before automatic selection. A samples
F12 as a held level during that window after F sees the make code. A
latched recovery choice inhibits automatic commit until explicit
selection. While the guest runs, A edge-detects the held key signals and
sequences soft guest reset on F11 or return to the loader on F12. Return
takes priority if both edges arrive together. A key held across an
ownership transition must be released before it can trigger another
action. SW2 asserts `board_reset_n` via U6, so A asserts fabric reset
asynchronously and restarts the boot path on qualified release.

E drains staging and initialization writes before commit and keeps staging
and the descriptor stable until completion. A accepts a request once
while the loader owns the machine, then disarms acceptance until the
producer drops valid. The commit latch performs the following steps
in order.

1. Check readiness, the staged set and the pending descriptor. Quiesce the
   CPU, quiesce media and gate new memory work. Permit accepted work to
   complete its dependent accesses, then wait for `media_idle` and
   `mem_idle`.
2. Give the promotion sequencer exclusive loader-port access. Copy each
   populated staging slot to its fixed active slot and wait for write
   drain. Unpopulated slots remain inaccessible via the ROM mask. Keep
   both CPU and guest peripherals held in reset.
3. Atomically publish the configuration and mount descriptors. Hide the
   boot overlay and hand the media path to guest service. Release guest
   peripherals and the CPU after the guest clocks and SDRAM are ready.
   The first guest fetch is from address zero in logical ROM slot 0.

A failed attempt or clock/memory loss in promotion leaves or returns the
machine to the loader. If promotion already asserted CPU reset, the
loader restarts at address zero and reads the retained error status as
soon as its clock is available. A partially promoted set is invalid until
a fresh successful promotion. Boot error codes shared with the diagnostic display
are 0 success, 1 storage unavailable, 2 ROM length/order/CRC invalid, 3
profile unsupported, 4 memory/clock unavailable, 5 promotion failed, 6
media invalid, 7 aborted. Other codes are reserved. A normal guest reset
or return request stops the CPU from starting new accesses, quiesces
media and drains accepted transactions before resetting the guest clients.
Guest reset restarts at address zero with active ROMs, configuration and
media ownership preserved. Return places the boot overlay back at zero
before CPU reset release. E keeps dirty-media bookkeeping through this
transition.

## Board evidence and discrepancies

[pins.csv](../../boards/trhmsx_v151/pins.csv) covers the requested
interfaces for the EP1C12Q240C8N. `fpga_net` is the net on the U1 pad.
`board_net` is the net on the endpoint shown. Series termination and DAC
paths can put them on different nets. The full names come from matching
v1.51 PCB pads because IPC-D-356 uppercases and truncates long names.
`direction` is from U1 in the Spectrum build, with `config_*` using U1
directions during Active Serial boot. `release` means a high-impedance
FPGA input without a fabric output driver. Listed FPGA idle output values
apply after configuration. Bench and Quartus evidence are open.

| Status | Evidence |
|---|---|
| `ipc_qsf` | IPC pad and board path checked against the v1.51 PCB and OCM package assignment. |
| `ipc_qsf_electrical_open` | Same continuity check, with an unresolved voltage interface. |
| `ipc_device` | IPC connectivity and component pin documentation, including configuration pins outside fabric assignments. |
| `ipc` | IPC and PCB evidence, including connector-only or physically unconnected pads. |

- **Clock and U5.** U1-28 and U1-29 receive the same buffered Y1 oscillator
  via R9 and R8 respectively. The donor name `pExtClk` refers to the
  second oscillator input. U1-38 (OCM `pMemClk`) reaches `/MCLK` at
  U5-38 through R10, 22 Ω. The BOM's full nominal 32 MiB U5 has A0–A12
  and BA0/1 routed in the production IPC. The 4 MiB figure is a working
  ceiling. The OCM device field `EP1C12Q240C8` omits the BOM ordering
  suffix `N`. [Altera EP1C12 pin list](https://cdrdv2-public.intel.com/676497/ep1c12.pdf)
- **SD.** U1-65/63/64/62 agree with Section 2, across the series arrays.
  J4-9 has an explicit unconnected pad. R1 and R2 pull CMD and CLK to
  3.3 V on the card side. The published IPC shows no board pull-up on
  DAT3. Output idle states apply once the FPGA owns the pins.
- **PS/2 electrical hold.** R13 and R14 are 2.2 kΩ pull-ups to **+5 V**
  on shared J7/CH559 nets. RN22 inserts 100 Ω between those nets and U1
  pins 67/68. Source-level receive-only direction does not establish
  5 V tolerance. The donor QSF has weak pulls on both inputs and no
  explicit `PCI_IO ON` on these ports, although it sets that option
  for many other pins. These board pull-ups are present with J7 empty.
  Before board use, validate idle voltage, the clamp/series-current
  limits and CH559 sharing on the actual unit. Require verified
  conditioning if the input limit is exceeded. Future transmit uses
  only drive-low/release.
  [Altera Cyclone voltage interfacing](https://cdrdv2-public.intel.com/654560/cyc_c51011.pdf)
- **VGA and audio naming.** The RGB endpoints are `/VR_SC`, `/VG_SY`
  and `/VB_CV`; R and G are also wired to J18. The QSF's `pVideoDat`
  and `pVideoClk` reach J14-15 and J14-12 (DDC SDA/SCL). Keep released.
  J11's schematic labels are T, S and G. T is `/SOUND_L`, S is
  `/SOUND_R`, and G is ground. The six left/right bits reach those
  contacts through their separate DAC networks and C29/C28. J11 has
  no EAR path.
- **Joystick strobe.** The connector's pin 8 is the strobe/common
  return and pin 9 is ground. The 10 kΩ board pulls on pin 8 go to
  3.3 V. The OCM strobes are PSG Port B bits 4/5 and reset low.
  Drive both strobes low for passive conventional sticks. The two
  buttons and four directions per port are inputs with 3.3 V pulls
  and active-low switches. Verify both ports with a physical stick.
- **J8 and JTAG.** The board names `/AS_DI` (J8-7/U1-25/U8-2)
  and `/AS_DO` (J8-9/U1-37/U8-5) refer to the FPGA side. U8-2
  is DATA out and U8-5 is ASDI. J8-6 `/C_CE` is nCE with a
  pulldown. `/C_STAT` is nSTATUS on U1-146 and RN12, with no
  J8 connection. JTAG TCK/TMS/TDO/TDI are U1-147/148/149/155,
  tied to ground/3.3 V/unconnected/3.3 V respectively. Use EPCS4
  Active Serial programming and keep a complete known-good flash
  image. A Spectrum POF needs its own conversion settings. Preserve
  the original EPBIOS offset only in the OCM recovery image.
  [Altera EP1C12 pin list](https://cdrdv2-public.intel.com/676497/ep1c12.pdf)
  [Altera EPCS4 pin definitions](https://cdrdv2-public.intel.com/654137/ds_scg.pdf)
  [Altera USB-Blaster header table](https://www.intel.com/content/dam/support/us/en/programmable/support-resources/bulk-container/pdfs/literature/ug/archives/ug-usb-blstr-15.1.pdf)
- **Cartridge slots.** J16 is CART1 and J13 is CART2. `/SLTSL1`
  and `/SLTSL2` are separate. Selections and active-low command
  outputs idle high. DQ/address/reserved and cartridge-driven pins
  are released. U1-144 (`pCpuClk`) and U1-152 (`pSltClk`) are
  tied on the FPGA side of RN6. Hold 144 low and 152 as an input.
  U1-153 is the board's active-low cold-reset input. It receives
  `/RESET` from U6-6 through RN6, shared with both ports. SW2
  actuates U6 via its DC input. `/MERQ` is the PCB spelling of the
  active-low memory request. Connector power rails remain live when the
  board supplies them. Idle outputs apply after configuration.
- **ESP naming.** The QSF's `pUsbP1` and `pUsbN1` are ESP UART
  paths, on J2-2 and J2-7. Both pads are released. The QSF also assigns
  `pUsbN2/pUsbP2` to U1-238/239, which have unconnected PCB pads
  in v1.51. J2-6 is wired to J17, independently of the FPGA.

Board source paths at the revisions in
[the vendor inventory](../VENDOR_INVENTORY.md) are
`trhmsx/hardware/trhmsx/production/netlist.ipc`, `production/bom.csv`,
`trhmsx.kicad_pcb` and `trhmsx.kicad_sch`, together with
`ocm-pld-dev/esemsx3/emsx_top_common.qsf`. The OCM source corroborates
the joystick strobe, ESP UART and cartridge direction roles.
