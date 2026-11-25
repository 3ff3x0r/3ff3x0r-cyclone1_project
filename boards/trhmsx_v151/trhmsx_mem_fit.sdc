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

# Micron 256Mb SDR SDRAM datasheet 256Mb_sdr.pdf, Rev. N, -75/-7E at CL3.
# Address, command, CKE, DQM and write DQ use 1.5 ns setup and 0.8 ns hold.
# Read DQ uses 5.4 ns tAC max and 3.0 ns tOH min at the datasheet load.
# The separate no-load estimates in the datasheet are tAC 4.6 and tOH 1.8 ns.
set sdram_setup 1.5
set sdram_hold 0.8
set sdram_tac 5.4
set sdram_toh 3.0

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

# With e0 leading c0, a READ launched at c0[0] is registered at e0[1].
# Micron CL3 (Fig. 19) launches data at e0[3] and holds through e0[4] + tOH.
# The current controller captures at c0[5]. Time setup from e0[3] and hold
# from e0[4] so the report exposes a capture beyond the valid window.
set_multicycle_path -from $sdram_dq_ports -to $fabric_clock -setup -end 3
set_multicycle_path -from $sdram_dq_ports -to $fabric_clock -hold -end 0
