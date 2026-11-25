#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
build=$(mktemp -d "${TMPDIR:-/tmp}/trhmsx-tap-checks.XXXXXX")
trap 'rm -rf -- "$build"' EXIT

rtl=rtl/media/tap_player.v
tb=rtl/media/tb/tap_player_tb.v

if ! verilator --lint-only -Wall --language 1364-2001 "$rtl" > "$build/lint.log" 2>&1; then
    cat "$build/lint.log" >&2
    exit 1
fi
printf 'PASS Verilator Verilog-2001 lint\n'

yosys -Q -T -q -p '
    read_verilog rtl/media/tap_player.v
    hierarchy -check -top tap_player
    proc
    flatten
    check -assert
    scc -expect 0
    select -assert-none t:$dlatch t:$adlatch t:$dlatchsr t:$_DLATCH* t:$_DLATCHSR*
'
printf 'PASS Yosys structural check, zero combinational loops and zero latches\n'

iverilog -g2001 -Wall -Wno-timescale -s tap_player_tb -o "$build/tap_player.vvp" "$tb" "$rtl"
vvp "$build/tap_player.vvp"
