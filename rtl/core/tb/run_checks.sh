#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
build=$(mktemp -d "${TMPDIR:-/tmp}/spectrum-core.XXXXXX")
printf 'Build and logs are in %s\n' "$build"

run_iverilog() {
    local top=$1 language=$2
    shift 2
    iverilog "$language" -s "$top" -o "$build/$top.vvp" "rtl/core/tb/$top.v" "$@"
    vvp "$build/$top.vvp" | tee "$build/$top.log"
    if rg -q '^FAIL' "$build/$top.log" || ! rg -q '^PASS' "$build/$top.log"; then
        return 1
    fi
}

run_iverilog spectrum_mmu_tb -g2001 rtl/core/spectrum_mmu.v
if [[ ${1:-} == --mmu-only ]]; then
    exit 0
fi

donor=vendor/ZX_Spectrum-128K_MIST/T80
rtl=(rtl/core/{core_subsystem,spectrum_mmu,spectrum_io,spectrum_ula}.v)
wrapper=rtl/core/spectrum_cpu.vhd
native_tb=rtl/core/tb/spectrum_cpu_tb.vhd
ghdl_opts=(--std=93 -fsynopsys -fexplicit --syn-binding)

analyze_cpu() {
    local work=$1 source=$2
    mkdir -p "$work"
    # T80_MCode's local F case-insensitively shadows the flags input.
    ghdl -a "${ghdl_opts[@]}" --workdir="$work" -Werror -Wno-hide \
        "$donor"/T80_{Pack,ALU,MCode,Reg}.vhd "$source" "$donor/T80pa.vhd"
    ghdl -a --std=93 --workdir="$work" -Werror "$wrapper" "$native_tb"
    (cd "$work" && ghdl -e "${ghdl_opts[@]}" -Werror spectrum_cpu_tb)
}

run_native() {
    local work=$1
    (cd "$work" && ghdl -r "${ghdl_opts[@]}" spectrum_cpu_tb \
        --ieee-asserts=disable-at-0 --assert-level=error) > "$work/simulation.log"
    sed -n 's/^.*: TRACE /TRACE /p' "$work/simulation.log" > "$work/trace.log"
    rg 'PASS native' "$work/simulation.log"
}

analyze_cpu "$build/native" "$donor/T80.vhd"
run_native "$build/native"

# Keep the vendor tree untouched. GHDL synthesis requires equal-width AND
# operands. Widen this low-three-bit mask to the width of ioq in scratch.
sed 's/ioq and x"7"/ioq and "000000111"/' "$donor/T80.vhd" > "$build/T80.vhd"
analyze_cpu "$build/synth" "$build/T80.vhd"
run_native "$build/synth"
diff -u "$build/native/trace.log" "$build/synth/trace.log"
printf 'PASS native bus trace matches the GHDL synthesis input\n'

# GHDL requires --latches for its treatment of the donor's enabled
# registers with asynchronous reset. The Yosys flow below rejects any
# latch cell in the resulting integrated circuit.
ghdl synth "${ghdl_opts[@]}" -Werror --workdir="$build/synth" --latches \
    --out=verilog spectrum_cpu > "$build/cpu_netlist.v"

# Lint the handwritten Verilog at the real synthesized VHDL boundary.
# Executable tests and Yosys use the full translated CPU.
awk '
    /^module spectrum_cpu([[:space:]]|$)/ { copying = 1 }
    copying { print }
    copying && /\);[[:space:]]*$/ { exit }
' "$build/cpu_netlist.v" > "$build/spectrum_cpu.v"
cat >> "$build/spectrum_cpu.v" <<'VERILOG'
    wire unused_inputs = &{clk_sys, reset_n, ce_p, ce_n, int_n, data_in};
    assign {m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n} = 6'b111111;
    assign addr = 16'd0;
    assign data_out = 8'd0;
endmodule
VERILOG
verilator --lint-only -Wall --language 1364-2001 --top-module core_subsystem \
    "${rtl[@]}" "$build/spectrum_cpu.v"
printf 'PASS Verilog-2001 lint\n'

cat > "$build/core.ys" <<YOSYS
read_verilog ${rtl[*]} "$build/cpu_netlist.v"
hierarchy -check -top core_subsystem
proc
flatten
opt
memory_collect
check -assert
scc -expect 0
select -assert-none t:\$dlatch t:\$adlatch t:\$dlatchsr t:\$_DLATCH*
select -assert-none t:\$mem*
stat
YOSYS
yosys -Q -T -s "$build/core.ys" > "$build/yosys.log"
printf 'PASS integrated Yosys check, zero combinational loops, latches and inferred RAMs\n'

run_iverilog core_subsystem_tb -g2001 "${rtl[@]}" "$build/cpu_netlist.v"
run_iverilog spectrum_ula_tb -g2001 rtl/core/spectrum_ula.v
# Ticket B's existing SDRAM verification model uses SystemVerilog casts.
run_iverilog core_sdram_tb -g2012 "${rtl[@]}" "$build/cpu_netlist.v" \
    rtl/memory/*.v rtl/memory/tb/sdram_x16_model.v rtl/video/video_clock_enables.v
