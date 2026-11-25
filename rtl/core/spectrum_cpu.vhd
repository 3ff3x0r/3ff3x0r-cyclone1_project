library ieee;
use ieee.std_logic_1164.all;

-- Bind the project T80pa adaptation in its standard Z80 mode.
entity spectrum_cpu is
    port (
        clk_sys     : in  std_logic;
        reset_n     : in  std_logic;
        ce_p        : in  std_logic;
        ce_n        : in  std_logic;
        int_n       : in  std_logic;
        m1_n        : out std_logic;
        mreq_n      : out std_logic;
        iorq_n      : out std_logic;
        rd_n        : out std_logic;
        wr_n        : out std_logic;
        rfsh_n      : out std_logic;
        read_on_neg : out std_logic;
        addr        : out std_logic_vector(15 downto 0);
        data_in     : in  std_logic_vector(7 downto 0);
        data_out    : out std_logic_vector(7 downto 0)
    );
end spectrum_cpu;

architecture rtl of spectrum_cpu is
begin
    cpu : entity work.T80pa
        generic map (Mode => 0)
        port map (
            CLK => clk_sys, RESET_n => reset_n, CEN_p => ce_p, CEN_n => ce_n,
            WAIT_n => '1', INT_n => int_n, NMI_n => '1', BUSRQ_n => '1',
            M1_n => m1_n, MREQ_n => mreq_n, IORQ_n => iorq_n,
            RD_n => rd_n, WR_n => wr_n, RFSH_n => rfsh_n, ReadOnNeg => read_on_neg,
            HALT_n => open, BUSAK_n => open, A => addr, DI => data_in,
            DO => data_out, REG => open, OUT0 => '0', DIRSet => '0',
            DIR => (others => '0')
        );
end rtl;
