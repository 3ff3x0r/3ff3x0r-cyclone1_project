#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
baseline=$(realpath -- "${1:?Supply the checkout with the original CPU clock}")
build=$(mktemp -d "${TMPDIR:-/tmp}/trhmsx-clock-comparison.XXXXXX")
printf 'CPU clock comparison logs in %s\n' "$build"

ghdl_opts=(--std=93 -fsynopsys -fexplicit --syn-binding)
harness=(rtl/core/tb/core_sdram_tb.v rtl/memory/tb/sdram_x16_model.v
         rtl/video/video_clock_enables.v)

build_fixture() {
    local tag=$1 tree=$2
    shift 2
    local donor="$tree/vendor/ZX_Spectrum-128K_MIST/T80"
    local core="$tree/rtl/core"
    local t80pa="$core/T80pa.vhd"
    if [[ ! -f $t80pa ]]; then
        t80pa="$donor/T80pa.vhd"
    fi
    mkdir "$build/$tag"
    ghdl -a "${ghdl_opts[@]}" --workdir="$build/$tag" -Werror -Wno-hide \
        "$donor"/T80_{Pack,ALU,MCode,Reg}.vhd "$core/T80.vhd" \
        "$t80pa" "$core/spectrum_cpu.vhd"
    ghdl synth "${ghdl_opts[@]}" --workdir="$build/$tag" --latches \
        -Werror --out=verilog spectrum_cpu > "$build/$tag/cpu.v"
    # The ULA and mirror in each checkout must use the same read latency.
    iverilog -g2012 -s core_sdram_tb -o "$build/$tag.vvp" "${harness[@]}" "$tree"/rtl/memory/*.v \
        "$core"/{core_subsystem,spectrum_mmu,spectrum_io,spectrum_ula}.v "$build/$tag/cpu.v" "$@"
}

build_fixture baseline "$baseline"
build_fixture prototype "$PWD" -DREGISTERED_CPU_CLOCK \
    rtl/core/tb/cpu_clock_model.v rtl/core/cpu_clock_bridge.v

run_fixture() {
    local tag=$1 label=$2
    shift 2
    vvp -N "$build/$tag.vvp" +trace_bus "$@" > "$build/$label.log"
    ! rg '^FAIL|^FATAL' "$build/$label.log" && rg -q '^PASS SDRAM stress' "$build/$label.log"
}

# Compare pre-phase bus signals and actual input sample edges. The live DI
# value on an earlier phase can differ while a memory response is pending.
trace() {
    awk '/^TRACE [CDRW] / {print} /^TRACE P / {NF--; print}' "$1"
}

pids=()
for timing in {0..5}; do
    run_fixture baseline "baseline-$timing" "+timing=$timing" &
    pids+=("$!")
    for align in 0 1; do
        run_fixture prototype "prototype-$timing-$align" "+timing=$timing" "+cpu_align=$align" &
        pids+=("$!")
    done
done
for pid in "${pids[@]}"; do
    wait "$pid"
done

for timing in {0..5}; do
    for align in 0 1; do
        original="$build/baseline-$timing.log"
        candidate="$build/prototype-$timing-$align.log"
        # Physical CPU edges and fabric writes are reported by different
        # clocks. Compare chronological order within each event type.
        for event in P C D R W; do
            diff -u <(trace "$original" | awk -v e="$event" '$2 == e') \
                    <(trace "$candidate" | awk -v e="$event" '$2 == e')
        done
        printf 'PASS bus phases, sampled data, contention, CPU write order (timing %s, alignment %s)\n' \
            "$timing" "$align"
    done
done
rg '^METRICS|^PHASES' "$build"/*.log

run_fixture baseline mixed-baseline +timing=4 +loader_writes
for align in 0 1; do
    run_fixture prototype "mixed-prototype-$align" +timing=4 +loader_writes "+cpu_align=$align"
done
for label in mixed-baseline mixed-prototype-0 mixed-prototype-1; do
    diff -u <(awk '$2 == "A" {$2 = "W"; print}' "$build/$label.log") \
            <(awk '$2 == "M" {$2 = "W"; print}' "$build/$label.log")
    printf 'PASS SDRAM dispatch follows accepted CPU/loader write order (%s)\n' "$label"
done
for align in 0 1; do
    if ! cmp -s <(rg '^TRACE A ' "$build/mixed-baseline.log") \
                <(rg '^TRACE A ' "$build/mixed-prototype-$align.log"); then
        printf 'CPU/loader write interleaving differs from the baseline (alignment %s)\n' "$align"
    fi
done

for variant in baseline prototype; do
    for align in 0 1; do
        log="$build/shared-$variant-$align.log"
        vvp -N "$build/$variant.vvp" +same_byte +timing=4 "+cpu_align=$align" > "$log"
        rg '^PASS shared-byte arbitration' "$log"
    done
done
