library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_pwm_crc_bridge_tb is
-- Testbench не имеет портов
end spi_pwm_crc_bridge_tb;

architecture Behavior of spi_pwm_crc_bridge_tb is
    -- Компонент моста
    component spi_pwm_crc_bridge is
        Port (
            clk        : in  STD_LOGIC;
            rst_n      : in  STD_LOGIC;
            spi_sck    : in  STD_LOGIC;
            spi_cs_n   : in  STD_LOGIC;
            spi_mosi   : in  STD_LOGIC;
            spi_miso   : out STD_LOGIC;
            duty_out   : out unsigned(11 downto 0);
            valid_cmd  : out STD_LOGIC
        );
    end component;

    -- Сигналы для подключения
    signal clk        : STD_LOGIC := '0';
    signal rst_n      : STD_LOGIC := '0';
    signal spi_sck    : STD_LOGIC := '0';
    signal spi_cs_n   : STD_LOGIC := '1';
    signal spi_mosi   : STD_LOGIC := '0';
    signal spi_miso   : STD_LOGIC;
    signal duty_out   : unsigned(11 downto 0);
    signal valid_cmd  : STD_LOGIC;

    constant CLK_PERIOD : time := 5 ns; -- 200 МГц
    constant SPI_PERIOD : time := 100 ns; -- 10 МГц для SPI

    -- Процедура эмуляции отправки 24 бит мастером (SPI Mode 0)
    procedure send_spi_packet(
        data_word : in STD_LOGIC_VECTOR(23 downto 0);
        signal sck  : out STD_LOGIC;
        signal mosi : out STD_LOGIC;
        signal cs_n : out STD_LOGIC
    ) is
    begin
        cs_n <= '0';
        wait for SPI_PERIOD;
        for i in 23 downto 0 loop
            mosi <= data_word(i);
            wait for SPI_PERIOD / 2;
            sck <= '1';
            wait for SPI_PERIOD / 2;
            sck <= '0';
        end loop;
        wait for SPI_PERIOD;
        cs_n <= '1';
        wait for SPI_PERIOD * 2;
    end procedure;

begin
    -- Инстанцирование DUT (Device Under Test)
    DUT: spi_pwm_crc_bridge port map (
        clk => clk, rst_n => rst_n,
        spi_sck => spi_sck, spi_cs_n => spi_cs_n,
        spi_mosi => spi_mosi, spi_miso => spi_miso,
        duty_out => duty_out, valid_cmd => valid_cmd
    );

    -- Генератор тактов (200 МГц)
    clk_process: process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
    end process;

    -- Основной процесс тестирования
    stim_proc: process
    begin
        -- Инициализация и сброс
        rst_n <= '0';
        wait for 50 ns;
        rst_n <= '1';
        wait for 50 ns;

        -- Тест 1: Валидный пакет
        -- Данные: 0x05DC (Duty = 1500), CRC-8 ATM для 0x05DC = 0x8A
        -- Итоговое слово: 0x05DC8A
        send_spi_packet(x"05DC8A", spi_sck, spi_mosi, spi_cs_n);
        
        wait for 200 ns;

        -- Тест 2: Битый пакет (ошибка в данных)
        -- Данные: 0x05DD (Duty = 1501), CRC-8 отправляем старый (0x8A)
        -- Ожидаемый результат: valid_cmd не должен подняться
        send_spi_packet(x"05DD8A", spi_sck, spi_mosi, spi_cs_n);

        wait; -- Остановка симуляции
    end process;
end Behavior;
