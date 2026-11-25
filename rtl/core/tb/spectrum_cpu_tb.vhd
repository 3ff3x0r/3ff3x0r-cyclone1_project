library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spectrum_cpu_tb is
end spectrum_cpu_tb;

architecture test of spectrum_cpu_tb is
    signal clk_sys : std_logic := '0';
    signal reset_n, ce_p, ce_n : std_logic := '0';
    signal done : boolean := false;
    signal m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n : std_logic;
    signal addr : std_logic_vector(15 downto 0);
    signal data_in, data_out : std_logic_vector(7 downto 0);
    type rom_type is array (0 to 7) of std_logic_vector(7 downto 0);
    -- LD A,19 / ADD A,23 / LD (4000),A / HALT.
    constant rom : rom_type := (x"3e", x"13", x"c6", x"17", x"32", x"00", x"40", x"76");
begin
    clk_sys <= not clk_sys after 5 ns when not done else '0';
    cpu : entity work.spectrum_cpu
        port map (
            clk_sys => clk_sys, reset_n => reset_n, ce_p => ce_p, ce_n => ce_n,
            int_n => '1', m1_n => m1_n, mreq_n => mreq_n, iorq_n => iorq_n,
            rd_n => rd_n, wr_n => wr_n, rfsh_n => rfsh_n, addr => addr,
            data_in => data_in, data_out => data_out, read_on_neg => open
        );

    process(addr)
    begin
        data_in <= x"ff";
        if addr(15 downto 3) = "0000000000000" then
            data_in <= rom(to_integer(unsigned(addr(2 downto 0))));
        end if;
    end process;

    process
        variable saw_write : boolean := false;
        variable fetches : natural := 0;
        variable read_edge, write_edge : boolean := false;
    begin
        for tick in 0 to 200 loop
            wait until falling_edge(clk_sys);
            if tick < 3 then
                reset_n <= '0';
            else
                reset_n <= '1';
                if tick mod 2 = 1 then
                    ce_p <= '1';
                    ce_n <= '0';
                else
                    ce_p <= '0';
                    ce_n <= '1';
                end if;

                if mreq_n = '0' and rd_n = '0' and not read_edge then
                    report "TRACE R " & integer'image(tick) & " " &
                        integer'image(to_integer(unsigned(addr))) & " " & std_logic'image(m1_n);
                    if m1_n = '0' then
                        fetches := fetches + 1;
                    end if;
                end if;
                read_edge := mreq_n = '0' and rd_n = '0';

                if mreq_n = '0' and wr_n = '0' and not write_edge then
                    assert addr = x"4000" and data_out = x"2a" and not saw_write
                        report "Unexpected native Z80 write" severity failure;
                    report "TRACE W " & integer'image(tick) & " " &
                        integer'image(to_integer(unsigned(addr))) & " " &
                        integer'image(to_integer(unsigned(data_out)));
                    saw_write := true;
                end if;
                write_edge := mreq_n = '0' and wr_n = '0';
            end if;
        end loop;
        assert saw_write and fetches >= 4 report "Native T80pa did not execute ROM" severity failure;
        report "PASS native VHDL-93 T80pa execution";
        done <= true;
        wait;
    end process;
end test;
