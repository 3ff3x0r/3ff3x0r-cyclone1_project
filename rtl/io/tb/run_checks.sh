#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
root=$PWD
if (( $# > 1 )); then
    printf 'Usage: %s [ticket-c-worktree]\n' "$0" >&2
    exit 2
fi
build=$(mktemp -d /tmp/trhmsx-ticket-f.XXXXXX)
printf 'Build and logs are in %s\n' "$build"

input_rtl=(rtl/io/{input_subsystem,ps2_receiver,spectrum_ps2_keyboard}.v)
audio_rtl=(rtl/audio/{audio_subsystem,ay_3_8912}.v)

check_rtl() {
    local top=$1
    shift
    verilator --lint-only -Wall --language 1364-2001 --top-module "$top" "$@"
    {
        printf 'read_verilog'
        local source
        for source in "$@"; do
            printf ' "%s"' "$root/$source"
        done
        printf '\n'
        cat <<YOSYS
hierarchy -check -top $top
proc
flatten
opt
memory_collect
check -assert
scc -expect 0
select -assert-none t:\$dlatch t:\$adlatch t:\$dlatchsr t:\$_DLATCH* t:\$mem*
synth -top $top -lut 4
check -assert
stat
YOSYS
    } > "$build/$top.ys"
    (cd -- "$build" && yosys -Q -T -s "$top.ys") > "$build/$top.yosys.log"
    printf 'PASS %s hierarchy/check, zero loops, latches and inferred memories\n' "$top"
    rg ' +[0-9]+ +\$(lut|_DFF)' "$build/$top.yosys.log" | tail -n 4
}

run_iverilog() {
    local top=$1 fixture=$2
    shift 2
    # Compile the fixtures against both the strict RTL language and the
    # repository's standard Icarus simulation mode.
    iverilog -g2001 -Wall -Wno-timescale -s "$top" -o "$build/$top.2001.vvp" "$fixture" "$@"
    iverilog -g2012 -Wall -Wno-timescale -s "$top" -o "$build/$top.vvp" "$fixture" "$@"
    vvp "$build/$top.vvp" | tee "$build/$top.log"
    ! rg -q '^FAIL' "$build/$top.log" && rg -q '^PASS' "$build/$top.log"
}

check_rtl input_subsystem "${input_rtl[@]}"
check_rtl audio_subsystem "${audio_rtl[@]}"
run_iverilog input_subsystem_tb rtl/io/tb/input_subsystem_tb.v "${input_rtl[@]}"
run_iverilog audio_subsystem_tb rtl/audio/tb/audio_subsystem_tb.v "${audio_rtl[@]}"

if (( $# == 1 )); then
    core=$(realpath -- "$1/rtl/core")
    donor=$(realpath -- "$1/vendor/ZX_Spectrum-128K_MIST/T80")
    core_rtl=("$core"/{core_subsystem,spectrum_io,spectrum_mmu,spectrum_ula}.v)
    ghdl_opts=(--std=93 -fsynopsys -fexplicit --syn-binding)

    check_cpu() {
        local work=$1 cpu_source=$2
        mkdir -p "$work"
        (
            cd -- "$work"
            ghdl -a "${ghdl_opts[@]}" -Werror -Wno-hide \
                "$donor"/T80_{Pack,ALU,MCode,Reg}.vhd "$cpu_source" "$donor/T80pa.vhd"
            ghdl -a --std=93 -Werror "$core/spectrum_cpu.vhd" "$core/tb/spectrum_cpu_tb.vhd"
            ghdl -e "${ghdl_opts[@]}" -Werror spectrum_cpu_tb
            ghdl -r "${ghdl_opts[@]}" spectrum_cpu_tb \
                --ieee-asserts=disable-at-0 --assert-level=error > simulation.log
            rg 'PASS native' simulation.log
            sed -n 's/^.*: TRACE /TRACE /p' simulation.log > trace.log
        )
    }

    check_cpu "$build/native" "$donor/T80.vhd"
    # Use C's documented equal-width mask workaround for GHDL synthesis.
    sed 's/ioq and x"7"/ioq and "000000111"/' "$donor/T80.vhd" > "$build/T80.vhd"
    check_cpu "$build/synth" "$build/T80.vhd"
    diff -u "$build/native/trace.log" "$build/synth/trace.log"
    printf 'PASS original and scratch T80 VHDL-93 bus traces match\n'
    (
        cd -- "$build/synth"
        ghdl synth "${ghdl_opts[@]}" -Werror --latches --out=verilog spectrum_cpu
    ) > "$build/cpu_netlist.v"

    run_iverilog core_input_audio_tb rtl/io/tb/core_input_audio_tb.v \
        "${core_rtl[@]}" "$build/cpu_netlist.v" rtl/video/video_clock_enables.v \
        "${input_rtl[@]}" "${audio_rtl[@]}"
fi
