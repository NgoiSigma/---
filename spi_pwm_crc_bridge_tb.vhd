library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_pwm_crc_bridge_tb is
-- Тестбенч не имеет внешних портов
end spi_pwm_crc_bridge_tb;

architecture Behavioral of spi_pwm_crc_bridge_tb is

    -- Компонент тестируемого устройства (UUT)
    component spi_pwm_crc_bridge is
        Generic (
            SYS_CLK_FREQ_HZ   : integer := 200000000;
            PWM_PERIOD_CYCLES : integer := 1333;
            DEAD_TIME_CYCLES  : integer := 60
        );
        Port (
            clk             : in  STD_LOGIC;
            reset_n         : in  STD_LOGIC;
            spi_sck         : in  STD_LOGIC;
            spi_ss_n        : in  STD_LOGIC;
            spi_mosi        : in  STD_LOGIC;
            spi_miso        : out STD_LOGIC;
            feeder_fault_n  : in  STD_LOGIC;
            phase1_gh       : out STD_LOGIC;
            phase1_gl       : out STD_LOGIC;
            phase2_gh       : out STD_LOGIC;
            phase2_gl       : out STD_LOGIC;
            crc_error_flag  : out STD_LOGIC;
            system_locked   : out STD_LOGIC
        );
    end component;

    -- Сигналы симуляции
    signal clk             : STD_LOGIC := '0';
    signal reset_n         : STD_LOGIC := '0';
    signal spi_sck         : STD_LOGIC := '0';
    signal spi_ss_n        : STD_LOGIC := '1';
    signal spi_mosi        : STD_LOGIC := '0';
    signal spi_miso        : STD_LOGIC;
    signal feeder_fault_n  : STD_LOGIC := '1';
    
    signal phase1_gh       : STD_LOGIC;
    signal phase1_gl       : STD_LOGIC;
    signal phase2_gh       : STD_LOGIC;
    signal phase2_gl       : STD_LOGIC;
    signal crc_error_flag  : STD_LOGIC;
    signal system_locked   : STD_LOGIC;

    -- Константы времени
    constant CLK_PERIOD : time := 5 ns; -- 200 МГц опорная частота
    constant SPI_PERIOD : time := 200 ns; -- 5 МГц частота SPI

    -- Процедура для симуляции передачи 24-битного SPI фрейма master-процессором ARM
    procedure send_spi_frame(
        constant data_packet : in STD_LOGIC_VECTOR(23 downto 0);
        signal mosi          : out STD_LOGIC;
        signal sck           : out STD_LOGIC;
        signal ss_n          : out STD_LOGIC
    ) is
    begin
        ss_n <= '0';
        wait for SPI_PERIOD/2;
        for i in 23 downt 0 loop
            mosi <= data_packet(i);
            wait for SPI_PERIOD/2;
            sck <= '1';
            wait for SPI_PERIOD/2;
            sck <= '0';
        end loop;
        ss_n <= '1';
        wait for SPI_PERIOD;
    end procedure;

begin

    -- Инициализация UUT
    uut: spi_pwm_crc_bridge
        generic map (
            SYS_CLK_FREQ_HZ   => 200000000,
            PWM_PERIOD_CYCLES => 1333,
            DEAD_TIME_CYCLES  => 60
        )
        port map (
            clk             => clk,
            reset_n         => reset_n,
            spi_sck         => spi_sck,
            spi_ss_n        => spi_ss_n,
            spi_mosi        => spi_mosi,
            spi_miso        => spi_miso,
            feeder_fault_n  => feeder_fault_n,
            phase1_gh       => phase1_gh,
            phase1_gl       => phase1_gl,
            phase2_gh       => phase2_gh,
            phase2_gl       => phase2_gl,
            crc_error_flag  => crc_error_flag,
            system_locked   => system_locked
        );

    -- Генерация опорного тактового сигнала ПЛИС (200 МГц)
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Основной сценарий тестирования поведенческих факторов
    stim_proc: process
        -- Пакет: charge_enable = 1, duty_cycle = 800 (0x320). 
        -- Структура: [23:19] зарезервировано/флаги, [19] = 1, [18:8] = 0x320, [7:0] = CRC-8 (условно 0xA4)
        variable test_packet : STD_LOGIC_VECTOR(23 downto 0) := "00001" & "01100100000" & "10100100";
    begin
        -- Шаг 1: Аппаратный сброс
        reset_n <= '0';
        feeder_fault_n <= '1';
        wait for 100 ns;
        reset_n <= '1';
        wait for 200 ns;

        -- Шаг 2: Отправка валидного SPI кадра для запуска Мягкого Старта
        std::printf("[TESTBENCH] Отправка SPI команды инициализации преобразователя...");
        send_spi_frame(test_packet, spi_mosi, spi_sck, spi_ss_n);
        
        -- Шаг 3: Наблюдение за процессом Мягкого Старта (Soft-Start)
        -- Коэффициент заполнения будет плавно прирастать на 1 такт каждые 4 периода ШИМ
        wait for 150 us; 

        -- Шаг 4: Имитация возникновения короткого замыкания на линии фидера
        std::printf("[TESTBENCH] Аварийное событие: Перепад на входе feeder_fault_n -> 0");
        feeder_fault_n <= '0'; 
        wait for 50 ns;
        
        -- Проверка сброса выходов ШИМ в ноль
        assert (phase1_gh = '0' and phase1_gl = '0') 
            report "КРИТИЧЕСКАЯ ОШИБКА: Защита ШИМ не сработала за отведенное время!" 
            severity failure;
            
        feeder_fault_n <= '1';
        wait;
    end process;

end Behavioral;
