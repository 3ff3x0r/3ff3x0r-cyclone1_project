#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$repo_root"

build=$(mktemp -d "${TMPDIR:-/tmp}/spectrum_top_check.XXXXXX")
trap 'rm -rf -- "$build"' EXIT
mkdir -p "$build/synth"

donor=vendor/ZX_Spectrum-128K_MIST/T80
ghdl_opts=(--std=93 -fsynopsys -fexplicit --syn-binding)

# 1. Translate VHDL CPU wrapper to Verilog netlist
ghdl -a "${ghdl_opts[@]}" --workdir="$build/synth" -Werror -Wno-hide \
    "$donor"/T80_{Pack,ALU,MCode,Reg}.vhd rtl/core/T80.vhd rtl/core/T80pa.vhd
ghdl -a --std=93 --workdir="$build/synth" -Werror rtl/core/spectrum_cpu.vhd
ghdl synth "${ghdl_opts[@]}" -Werror --workdir="$build/synth" --latches \
    --out=verilog spectrum_cpu > "$build/cpu_netlist.v"

# 2. Extract stub for Verilator lint
awk '
    /^module spectrum_cpu([[:space:]]|$)/ { copying = 1 }
    copying { print }
    copying && /\);[[:space:]]*$/ { exit }
' "$build/cpu_netlist.v" > "$build/spectrum_cpu.v"
cat >> "$build/spectrum_cpu.v" <<'VERILOG'
    wire unused_inputs = &{clk_sys, reset_n, ce_p, ce_n, int_n, data_in};
    assign {m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n} = 6'b111111;
    assign read_on_neg = 1'b0;
    assign addr = 16'd0;
    assign data_out = 8'd0;
endmodule
VERILOG

rtl=(
    rtl/top/spectrum_top.v
    rtl/top/boot_orchestrator.v
    rtl/top/boot_bus_adapter.v
    rtl/memory/mem_subsystem.v
    rtl/memory/mem_arbiter.v
    rtl/memory/sdram_x16.v
    rtl/memory/screen_mirror.v
    rtl/core/core_subsystem.v
    rtl/core/cpu_clock_bridge.v
    rtl/core/spectrum_mmu.v
    rtl/core/spectrum_io.v
    rtl/core/spectrum_ula.v
    rtl/video/video_subsystem.v
    rtl/video/video_clock_enables.v
    rtl/video/video_scandoubler.v
    rtl/io/input_subsystem.v
    rtl/io/ps2_receiver.v
    rtl/io/spectrum_ps2_keyboard.v
    rtl/audio/audio_subsystem.v
    rtl/audio/ay_3_8912.v
    rtl/storage/boot_sd_bridge.v
    rtl/storage/sd_spi_reader.v
    rtl/media/tap_player.v
)

# 3. Verilator Verilog-2001 lint across the full hierarchy
verilator --lint-only -Wall --language 1364-2001 --top-module spectrum_top \
    "${rtl[@]}" "$build/spectrum_cpu.v"
printf 'PASS spectrum_top Verilog-2001 lint\n'

# 4. Yosys full-system structural check (zero loops, zero latches)
yosys -q -p "
    read_verilog ${rtl[*]} $build/cpu_netlist.v;
    hierarchy -check -top spectrum_top;
    proc; flatten; opt;
    check -assert;
    scc -expect 0;
    select -assert-none t:\$dlatch t:\$adlatch t:\$dlatchsr t:\$_DLATCH*
"
printf 'PASS spectrum_top Yosys check (0 loops, 0 latches)\n'

# 5. Unit testbenches
iverilog -g2001 -s boot_orchestrator_tb -o "$build/boot_orchestrator.vvp" \
    rtl/top/boot_orchestrator.v rtl/top/tb/boot_orchestrator_tb.v
vvp -N "$build/boot_orchestrator.vvp"

iverilog -g2001 -s boot_bus_adapter_tb -o "$build/boot_bus_adapter.vvp" \
    rtl/top/boot_bus_adapter.v rtl/top/tb/boot_bus_adapter_tb.v
vvp "$build/boot_bus_adapter.vvp"

iverilog -g2001 -s boot_completion_tb -o "$build/boot_completion.vvp" \
    rtl/core/{core_subsystem,cpu_clock_bridge,spectrum_mmu,spectrum_io,spectrum_ula}.v "$build/cpu_netlist.v" \
    rtl/top/boot_bus_adapter.v rtl/storage/boot_sd_bridge.v rtl/core/tb/cpu_clock_model.v \
    rtl/top/tb/boot_completion_tb.v
vvp -N "$build/boot_completion.vvp" "+cpu_align=${CPU_ALIGNMENT:-0}"

# 6. Mixed-language integration with the pin-level SDRAM model.
# The existing SDRAM model uses SystemVerilog casts.
iverilog -g2012 -s spectrum_top_tb -o "$build/spectrum_top.vvp" \
    "${rtl[@]}" "$build/cpu_netlist.v" rtl/memory/tb/sdram_x16_model.v \
    rtl/core/tb/cpu_clock_model.v rtl/top/tb/spectrum_top_tb.v
vvp -N "$build/spectrum_top.vvp" "+cpu_align=${CPU_ALIGNMENT:-0}"
