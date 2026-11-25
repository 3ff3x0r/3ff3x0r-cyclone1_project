# Ticket F input and audio

## Wiring

Add `rtl/io/{input_subsystem,ps2_receiver,spectrum_ps2_keyboard}.v` and
`rtl/audio/{audio_subsystem,ay_3_8912}.v` to the board project. All logical
connections below use the rising edge of `clk_sys`. The C endpoints are from
the local `ticket-c/core` worktree's `rtl/core/core_subsystem.v` and
`spectrum_io.v`. D's `video_clock_enables` is from commit `881821b`.

| Producer → consumer | Signals and width | Polarity and timing |
|---|---|---|
| D `video_clock_enables` → C `core_subsystem` | `ce_cpu`, `ce_ula`, `ce_psg` (1 each) | Active-high strobes. CPU is every second ULA tick and PSG is every fourth. D gates PSG with `cfg_psg_enable`. |
| C `core_subsystem.psg_ce` → F `audio_subsystem.ce_psg` | 1 | Active-high strobe. C further gates D's enable with fabric and guest reset, boot overlay, config validity and `cfg_psg_enable`. |
| F `input_subsystem` → C `core_subsystem`, or E's boot adapter | `key_matrix_n` (40), `joy1`, `joy2` (6 each) | Held active-low matrix and active-high joystick switches. C reads them during FE/Kempston cycles. F updates on fabric clocks independently of guest enables. |
| C `core_subsystem` → F `audio_subsystem` | `ay_req` (1), `ay_op` (2), `ay_wdata` (8) | High request for one fabric cycle. Operations 0/1/2 select/write/read. Writes and selects use the request edge independently of the PSG strobe. |
| F `audio_subsystem` → C `core_subsystem` | `ay_rdata` (8), `ear_bit` (1) | Combinational readback and positive-logic EAR. C samples during I/O reads. AY data is available before C's read request pulse. |
| C `core_subsystem` → F `audio_subsystem` | `mic_bit`, `beeper_bit` (1 each) | Held positive-logic outputs from FE bits 3 and 4. The DAC mixer samples them every fabric clock. |
| A → C, D and F | `cfg_psg_enable` (1) | Active-high latched descriptor field. Wire it to C, D and `audio_subsystem`. |
| A → C | `cfg_input_map_id`, `cfg_joy1_b_map`, `cfg_joy2_b_map` (2 each) | Latched descriptor fields. C uses them for combinational guest I/O decode. |
| A → F | `rst_n`, `guest_reset_n` (1 each) | Input and audio use active-low asynchronous fabric reset. Audio also samples active-low guest reset on rising fabric clock edges. |
| F `input_subsystem` → A and G | `soft_reset_key`, `recovery_key`, `tap_play_toggle`, `tap_rewind` (1 each) | Positive-logic F11/F12 held levels and one-clock F9/F10 pulses. |
| G and A → F `audio_subsystem` | `tap_ear_valid`, `tap_ear_bit`, `ear_idle_bit`, `mic_record` (1 each) | G's held digital TAP level wins while valid. A supplies the selected profile's idle level. A/E asserts recording mode for the left DAC. |
| F `audio_subsystem` → A | `audio_l`, `audio_r` (6 each), `mic_out` (1) | Registered unsigned DAC codes with zero on reset. `mic_out` is the clean positive-logic MIC level, gated by reset. |

The interface contract names D as the PSG enable producer. C's
`psg_ce` is the guest-qualified form to wire to F. C already merges
keyboard and joystick sources, ANDs the selected rows, and provides
the Kempston read at low byte `1F` in mapping 1. Wire F's raw logical
sticks to C in [up, down, left, right, A, B] order from bit 0. The
actual FE/AY path uses the frozen widths and operations directly.
[Frozen interfaces](../../docs/contracts/interfaces.md)

### Board connections

- Connect J7/CH559 clock and data as receive-only pads. The v1.51 PS/2
  electrical hold in the contract still applies to those shared 5 V pull-ups.
- Connect J15 to `joy1_n` and J10 to `joy2_n`, in bit 0 through bit 5 order
  from DE-9 pins 1, 2, 3, 4, 6, 7. The six board inputs idle high and a
  pressed switch pulls its input low. Drive both DE-9 pin 8 strobes low
  for conventional passive two-button sticks. Package assignments remain
  in the board pin table.
- Wire `audio_l` and `audio_r` to the two board DACs, bit 0 as LSB.
  Stock J11 is stereo output and supplies the recording route. A
  physical EAR adapter would need its own conditioned digital input and
  board-side source selection.

[v1.51 board pin table](../../boards/trhmsx_v151/pins.csv)

## Keyboard and joystick mappings

Each column pairs the Spectrum matrix key with a hexadecimal Set 2 code.
Rows match A8 through A15 and columns match FE bits 0 through 4.

| Row | Bit 0 | Bit 1 | Bit 2 | Bit 3 | Bit 4 |
|---|---|---|---|---|---|
| A8 | CAPS SHIFT / L Shift `12` | Z `1A` | X `22` | C `21` | V `2A` |
| A9 | A `1C` | S `1B` | D `23` | F `2B` | G `34` |
| A10 | Q `15` | W `1D` | E `24` | R `2D` | T `2C` |
| A11 | 1 `16` | 2 `1E` | 3 `26` | 4 `25` | 5 `2E` |
| A12 | 0 `45` | 9 `46` | 8 `3E` | 7 `3D` | 6 `36` |
| A13 | P `4D` | O `44` | I `43` | U `3C` | Y `35` |
| A14 | ENTER `5A` | L `4B` | K `42` | J `3B` | H `33` |
| A15 | SPACE `29` | SYMBOL SHIFT / L Ctrl `14` | M `3A` | N `31` | B `32` |

| PC key and Set 2 code | Mapping |
|---|---|
| R Shift `59`, R Ctrl `E0 14`, keypad Enter `E0 5A` | CAPS SHIFT, SYMBOL SHIFT, ENTER |
| Left/Down/Up/Right `E0 6B/72/75/74`, or keypad equivalents without E0 | CAPS SHIFT + 5/6/7/8 |
| Backspace `66`, Caps Lock `58`, Escape `76` | CAPS SHIFT + 0/2/SPACE |
| Period `49`, comma `41`, slash `4A`, semicolon `4C` | SYMBOL SHIFT + M/N/V/O, or T/R/C/Z with either Shift at make |
| Quote `52`, minus `4E`, equals `55` | SYMBOL SHIFT + 7/J/K, or P/0/L with either Shift at make |
| Left/right bracket `54/5B`, grave `0E`, backslash `5D`, keypad slash `E0 4A` | SYMBOL SHIFT + 8/9/7/B/V |
| F9/F10/F11/F12 `01/09/78/07` | Play/pause, rewind, soft reset, recovery. Host controls only. |

The receiver qualifies each synchronized clock transition with consecutive
samples at the new level. The `PS2_CLOCK_FILTER_CYCLES` parameter defaults to
16 samples, about 186 ns at 85.909 MHz. It checks complete 11-bit frames and
drops pending prefixes after a bad frame. A 250 µs gap between frame clocks
aborts a partial frame.
After fabric reset or a stalled low line, reception resumes after 250 µs
with both lines high. An uncompleted Set 2 prefix expires after 5 ms.
Per-source held state keeps physical modifiers, aliases and chord members
independent through typematic repeats and releases. A guest reset preserves
physical input. A fabric reset or keyboard BAT clears keyboard-held state.
Shifted punctuation retains its first-make chord through release and suppresses
CAPS SHIFT from both physical Shift keys while held. Cursor and editing
shortcuts can still assert CAPS SHIFT.
[IBM PS/2 Hardware Interface Technical Reference](https://www.jabse.com/L0lCTS9wYy9wczIvUGVyc29uYWxfU3lzdGVtXzJfSGFyZHdhcmVfSW50ZXJmYWNlX1RlY2huaWNhbF9SZWZlcmVuY2VfTWF5ODgucGRm)

C mapping 0 supplies Sinclair P1 6/7/8/9/0 and P2 1/2/3/4/5 in
left/right/down/up/A order. Mapping 1 supplies Kempston right/left/down/up/A
on bits 0–4 for P1 and retains Sinclair P2. Mapping 2 is keyboard only.
Each B binding can be disabled (0), SPACE (1), or SYMBOL SHIFT (2).
P1 code 3 in mapping 1 adds Kempston bit 5. A/E should default new game
profiles to mapping 0 with P1 B on SPACE and P2 B on SYMBOL SHIFT.
The frozen boot descriptor resets the B bindings to 0 until A publishes
the active config. Joystick A stays the standard fire button.

## AY and tape audio

`ay_3_8912.v` adapts the pinned MiST `ym2149.sv` and retains its notices
and 16-level AY amplitude curve. F uses a decoded bus interface, explicit
Verilog-2001 registers with a deterministic reset, and separate enable
division for tone, noise and the 16-step envelope. The unchanged donor
remains in the vendor checkout. Redistributed synthesized designs must
carry the donor notice in their accompanying materials.
[Pinned PSG source](https://github.com/sorgelig/ZX_Spectrum-128K_MIST/blob/9713924d41865f3d5712f9daf8fbd9b0489f8697/ym2149.sv)

D supplies the AY input clock rate directly. It averages 1.750000 MHz
for 48K/Pentagon, 1.773450 MHz for 128K/+2A/+3 and 1.787805 MHz for
TK. Tone cycles take `16*T` input ticks and the 17-bit noise register
shifts every `16*N`, with zero treated as one for both. The envelope
takes `16*E` ticks per level or 8 for zero. R13 writes restart its phase
and shape on the bus edge. Channel samples use the state entering each
PSG-enabled edge, which gives waveform transitions one PSG tick of
output latency. A disabled PSG holds its state and returns `FF` with
zero channel levels. Guest reset clears the PSG state.
[GI PSG data manual](https://pub.intvprime.com/ba4ef/ie/Programming/AY-3-8910-8912-Programmable-Sound-Generator-Data-Manual.pdf)
[MAME chip measurements](https://github.com/mamedev/mame/blob/master/src/devices/sound/ay8910.h)

R14 implements the single Port A with an unconnected input of `FF`.
R7 bit 6 selects input or output. R15 keeps the internal latch observed
on AY-3-8912 hardware. R7 bit 7 selects `FF` on input or the latch on
output. There is no external Port B connection.
[CPC register measurements](https://cpctech.cpcwiki.de/docs/psgnotes.htm)
[Spectrum +3 register 15 measurements](https://groups.google.com/g/comp.sys.sinclair/c/zEh3Fxx2jZQ)

The mixer produces left `(A+B)/16 + 32*beeper` and right
`(C+B)/16 + 32*beeper` with integer truncation. Each side spans 0–63.
Clean recording replaces left with 0 or 63 from MIC and keeps the
normal mix on right. TAP EAR and profile idle pass directly to FE bit 6.

## Verification

`rtl/io/tb/run_checks.sh` runs strict Verilator Verilog-2001 lint,
Icarus compilation in both language modes and the self-checking vvp
fixtures, plus Yosys hierarchy/check, latch/memory assertions and
generic four-input LUT mapping. Pass the C worktree path to include
native VHDL-93 T80 checks and the ROM-free CPU bus fixture with C and D.
That run reads the actual C RTL and donor in place and puts the
translated CPU, fixtures and logs under `/tmp`.

| Subsystem | Simulated | Yosys generic LUTs / flip-flops | Quartus fitted | Board tested |
|---|---|---:|---|---|
| Input | PS/2 frames and clock filtering, holds, rollover, reset, joystick and FE/Kempston | 312 / 174 | Pending | Pending |
| Audio | AY bus, 48/32/16-tick tone periods, noise, 16 envelope shapes, DAC, EAR, MIC and reset timing | 473 / 234 | Pending | Pending |
| C/D/F | T80 instructions through real FE, Kempston and AY with D clock enables |  | Pending | Pending |

Yosys inferred zero latches and zero memories in both F subtrees.
The LUT totals estimate generic combinational logic. Quartus placement,
logic-element packing and timing are open.
