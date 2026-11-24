# Target Profile: Altera Cyclone I FPGA (Vintage Silicon)
- **Toolchain:** Altera Quartus II v11.0 SP1 Web Edition (Running on a separate Windows XP machine).
- **Compilation Loop:** Human-in-the-loop. The agent generates the source files. The user manually runs compilation in the Quartus GUI and returns warnings/errors.
- **Language Standards:** Pure VHDL-93 or Verilog-2001. No modern standards (VHDL-2008, SystemVerilog) are supported by this compiler version.

# Hardware Architectural Constraints (Crucial)
1. **No Embedded Hardware Multipliers:** Cyclone I chips do not have DSP blocks. All mathematical operations (multiplication, division) must be designed using logic shifts (`shl`, `shr`), additions, or structural pipelines. Direct arithmetic multiplication (`*`) will fail or cause massive logic cell bloat.
2. **Memory Blocks (M4K):** Internal memory arrays must be structured completely synchronously (clocked reads and clocked writes) so the compiler maps them into physical M4K RAM blocks rather than wasting raw Logic Elements (LEs).
3. **Reset Strategy:** Use global asynchronous resets for registers where possible, matching the Cyclone I global clock/reset routing network to prevent timing issues.
