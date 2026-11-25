# Y1 feeds PLL1 on U1-28. Use the fitted PLL waveforms for c0 and e0.
create_clock -name clk_21m -period 46.561 [get_ports clk_21m]
derive_pll_clocks
derive_clock_uncertainty

set fabric_clock [get_clocks -nocase {*memory_pll*|clk[0]}]
set sdram_clock [get_clocks -nocase {*memory_pll*|extclk[0]}]
if {[get_collection_size $fabric_clock] != 1 || [get_collection_size $sdram_clock] != 1} {
    error "Expected one c0 and one e0 clock from memory_pll. Check report_clocks."
}
set sdram_clock_pad [get_ports sdram_clk]
set sdram_dq_ports [get_ports {sdram_dq[*]}]
set sdram_write_ports [get_ports {sdram_a[*] sdram_ba[*] sdram_dq[*] sdram_dqm[*]
                                sdram_cs_n sdram_ras_n sdram_cas_n sdram_we_n sdram_cke}]

# Micron 256Mb SDR SDRAM datasheet 256Mb_sdr.pdf, Rev. W, -75/-7E at CL3.
# Address, command, CKE, DQM and write DQ use 1.5 ns setup and 0.8 ns hold.
# Use the 5.4 ns loaded tAC maximum and 1.8 ns no-load tOHn minimum.
set sdram_setup 1.5
set sdram_hold 0.8
set sdram_tac 5.4
set sdram_toh 1.8

# PCB flight-time placeholders in ns. Replace with routed bounds for signoff.
set pcb_clk_min 0.0
set pcb_clk_max 0.0
set pcb_data_min 0.0
set pcb_data_max 0.0

# Reference the FPGA clock pad to include routing from e0 to U1-38.
set_output_delay -clock $sdram_clock -reference_pin $sdram_clock_pad \
    -max [expr {$sdram_setup + $pcb_data_max - $pcb_clk_min}] $sdram_write_ports
set_output_delay -clock $sdram_clock -reference_pin $sdram_clock_pad \
    -min [expr {-$sdram_hold + $pcb_data_min - $pcb_clk_max}] $sdram_write_ports
set_input_delay -clock $sdram_clock -reference_pin $sdram_clock_pad \
    -max [expr {$sdram_tac + $pcb_clk_max + $pcb_data_max}] $sdram_dq_ports
set_input_delay -clock $sdram_clock -reference_pin $sdram_clock_pad \
    -min [expr {$sdram_toh + $pcb_clk_min + $pcb_data_min}] $sdram_dq_ports

# A READ launched at c0[0] registers at e0[1]. CL3 launches DQ at e0[3].
# The c0 falling edge between e0[3] and e0[4] uses e0[3] for setup and
# e0[4] for hold with the default edge relationships. The captured data
# crosses to the next c0 rising edge on a timed half-cycle path.
# At the reported 2.909 ns e0 lead and 11.640 ns period, these read
# setup and hold edge separations are 8.729 ns and 2.911 ns, before
# applying the input delays, clock insertion delays and uncertainty.
