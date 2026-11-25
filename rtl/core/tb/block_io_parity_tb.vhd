library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.T80_Block_IO.all;

entity block_io_parity_tb is
end entity block_io_parity_tb;

architecture test of block_io_parity_tb is
begin
    process
        variable index_step : integer;
        variable decrement, expected : std_logic;
        variable id16_low : unsigned(7 downto 0);
        variable ioq : unsigned(8 downto 0);
        variable parity_bits : unsigned(7 downto 0);
        variable checked : natural := 0;
    begin
        for direction in 0 to 1 loop
            index_step := 1 - 2 * direction;
            decrement := '0';
            if direction = 1 then
                decrement := '1';
            end if;
            for reg_low in 0 to 7 loop
                -- Reference follows the donor's byte truncation, nine-bit sum
                -- and mask. Upper operand bits cannot affect the masked bits.
                id16_low := to_unsigned((reg_low + index_step) mod 256, 8);
                for operand_low in 0 to 7 loop
                    ioq := resize(id16_low, 9) + to_unsigned(operand_low, 9);
                    for bus_a in 0 to 255 loop
                        parity_bits := resize(ioq(2 downto 0), 8) xor to_unsigned(bus_a, 8);
                        expected := '1';
                        for bit_index in parity_bits'range loop
                            expected := expected xor parity_bits(bit_index);
                        end loop;
                        assert block_io_parity(std_logic_vector(to_unsigned(reg_low, 3)),
                                               std_logic_vector(to_unsigned(operand_low, 3)),
                                               decrement, std_logic_vector(to_unsigned(bus_a, 8))) = expected
                            report "Block-I/O parity mismatch at case " & integer'image(checked)
                            severity failure;
                        checked := checked + 1;
                    end loop;
                end loop;
            end loop;
        end loop;
        report "PASS block-I/O parity equivalence across " & integer'image(checked) & " combinations";
        wait;
    end process;
end architecture test;
