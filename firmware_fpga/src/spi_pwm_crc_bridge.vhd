library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_pwm_crc_bridge is
    Port (
        clk        : in  STD_LOGIC; -- Системная частота (200 МГц)
        rst_n      : in  STD_LOGIC;
        
        -- Интерфейс SPI (режим Slave)
        spi_sck    : in  STD_LOGIC;
        spi_cs_n   : in  STD_LOGIC;
        spi_mosi   : in  STD_LOGIC;
        spi_miso   : out STD_LOGIC; -- В данном случае не используется (только прием)
        
        -- Выход на ШИМ-контроллеры
        duty_out   : out unsigned(11 downto 0);
        valid_cmd  : out STD_LOGIC
    );
end spi_pwm_crc_bridge;

architecture RTL of spi_pwm_crc_bridge is
    signal shift_reg : STD_LOGIC_VECTOR(23 downto 0) := (others => '0');
    signal bit_cnt   : integer range 0 to 24 := 0;
    
    signal sck_r1, sck_r2 : STD_LOGIC := '0';
    signal sck_rising     : STD_LOGIC;
    
    -- Функция вычисления CRC-8 (Полином x^8 + x^2 + x + 1, 0x07) для 16 бит
    function calc_crc8(data : STD_LOGIC_VECTOR(15 downto 0)) return STD_LOGIC_VECTOR is
        variable crc : STD_LOGIC_VECTOR(7 downto 0) := x"00";
    begin
        for i in 15 downto 0 loop
            if (crc(7) xor data(i)) = '1' then
                crc := (crc(6 downto 0) & '0') xor x"07";
            else
                crc := crc(6 downto 0) & '0';
            end if;
        end loop;
        return crc;
    end function;

begin
    spi_miso <= 'Z'; -- Не передаем данные обратно мастеру

    -- Синхронизатор для SCK и выделение фронта
    process(clk)
    begin
        if rising_edge(clk) then
            sck_r1 <= spi_sck;
            sck_r2 <= sck_r1;
        end if;
    end process;
    sck_rising <= '1' when sck_r1 = '1' and sck_r2 = '0' else '0';

    -- Прием данных и валидация
    process(clk, rst_n)
        variable calc_crc : STD_LOGIC_VECTOR(7 downto 0);
    begin
        if rst_n = '0' then
            shift_reg <= (others => '0');
            bit_cnt <= 0;
            duty_out <= (others => '0');
            valid_cmd <= '0';
        elsif rising_edge(clk) then
            valid_cmd <= '0'; -- Импульс валидности сбрасывается
            
            if spi_cs_n = '0' then
                if sck_rising = '1' then
                    shift_reg <= shift_reg(22 downto 0) & spi_mosi;
                    if bit_cnt < 24 then
                        bit_cnt <= bit_cnt + 1;
                    end if;
                end if;
            else
                if bit_cnt = 24 then
                    -- CS поднялся, 24 бита получено. Проверяем CRC.
                    calc_crc := calc_crc8(shift_reg(23 downto 8));
                    if calc_crc = shift_reg(7 downto 0) then
                        duty_out <= unsigned(shift_reg(19 downto 8)); -- Извлекаем 12 бит из 16 бит данных
                        valid_cmd <= '1';
                    end if;
                end if;
                bit_cnt <= 0; -- Сброс счетчика для следующей транзакции
            end if;
        end if;
    end process;

end RTL;
