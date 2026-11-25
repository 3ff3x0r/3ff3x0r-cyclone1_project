# trhmsx_mem_fit.sdc derives PLL clocks and uncertainty first. Keep c1 and
# c0 related so TimeQuest checks both directions of the CPU bridge.
set cpu_clock [get_clocks -nocase {*memory_pll*|clk[1]}]
if {[get_collection_size $cpu_clock] != 1} {
    error "Expected one c1 CPU clock from memory_pll. Check report_clocks."
}
