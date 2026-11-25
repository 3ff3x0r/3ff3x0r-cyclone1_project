# Y1 through the board oscillator buffer to U1-28.
create_clock -name clk_21m -period 46.561 [get_ports {clk_21m}]
# ALTPLL supplies the 4x fabric clock. VGA uses a synchronous enable.
derive_pll_clocks
derive_clock_uncertainty
