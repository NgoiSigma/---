library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_pwm_crc_bridge is
    Generic (
        SYS_CLK_FREQ_HZ   : integer := 200000000; -- 200 МГц
        PWM_PERIOD_CYCLES : integer := 1333;      -- 150 кГц
        DEAD_TIME_CYCLES  : integer := 60         -- 300 нс
    );
    Port (
        clk             : in  STD_LOGIC;
        reset_n         : in  STD_LOGIC;
        
        -- 24-битный физический интерфейс SPI (Данные + CRC-8)
        spi_sck         : in  STD_LOGIC;
        spi_ss_n        : in  STD_LOGIC;
        spi_mosi        : in  STD_LOGIC;
        spi_miso        : out STD_LOGIC;
        
        feeder_fault_n  : in  STD_LOGIC;
        
        phase1_gh       : out STD_LOGIC;
        phase1_gl       : out STD_LOGIC;
        phase2_gh       : out STD_LOGIC;
        phase2_gl       : out STD_LOGIC;
        
        crc_error_flag  : out STD_LOGIC; -- Сигнализация проскальзывания ЭМП в кадре
        system_locked   : out STD_LOGIC
    );
end spi_pwm_crc_bridge;

architecture Behavioral of spi_pwm_crc_bridge is

    component interleaved_pwm_controller is
        Generic (
            SYS_CLK_FREQ_HZ   : integer;
            PWM_PERIOD_CYCLES : integer;
            DEAD_TIME_CYCLES  : integer
        );
        Port (
            clk             : in  STD_LOGIC;
            reset_n         : in  STD_LOGIC;
            duty_cycle      : in  STD_LOGIC_VECTOR(10 downto 0);
            charge_enable   : in  STD_LOGIC;
            feeder_fault_n  : in  STD_LOGIC;
            phase1_gh       : out STD_LOGIC;
            phase1_gl       : out STD_LOGIC;
            phase2_gh       : out STD_LOGIC;
            phase2_gl       : out STD_LOGIC;
            system_locked   : out STD_LOGIC
        );
    end component;

    -- Увеличенный 24-битный сдвиговый регистр
    signal bit_counter     : integer range 0 to 23 := 0;
    signal shift_reg       : STD_LOGIC_VECTOR(23 downto 0) := (others => '0');
    
    signal sck_sync        : STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
    signal ss_n_sync       : STD_LOGIC_VECTOR(1 downto 0) := (others => '1');
    signal mosi_sync       : STD_LOGIC_VECTOR(1 downto 0) := (others => '0');
    
    signal reg_duty_cycle  : STD_LOGIC_VECTOR(10 downto 0) := (others => '0');
    signal reg_charge_en   : STD_LOGIC := '0';
    signal internal_crc_err: STD_LOGIC := '0';

    -- Чистая комбинаторная функция вычисления CRC-8 (Полином 0x07, ATM-8)
    function calc_crc8_atm(data_in : STD_LOGIC_VECTOR(15 downto 0)) return STD_LOGIC_VECTOR is
        variable crc : std_logic_vector(7 downto 0) := (others => '0');
    begin
        crc := (others => '0'); -- Инициализация нулевым вектором
        for i in 15 downto 0 loop
            if (data_in(i) xor crc(7)) = '1' then
                crc := (crc(6 downto 0) & '0') xor "00000111"; -- Ксорим с полиномом 0x07
            else
                crc := (crc(6 downto 0) & '0');
            end if;
        end loop;
        return crc;
    end function;

    signal sck_rising_edge : STD_LOGIC;

begin

    crc_error_flag <= internal_crc_err;

    process(clk)
    begin
        if rising_edge(clk) then
            sck_sync  <= sck_sync(1 downto 0) & spi_sck;
            ss_n_sync <= ss_n_sync(0) & spi_ss_n;
            mosi_sync <= mosi_sync(0) & spi_mosi;
        end if;
    end process;

    sck_rising_edge <= '1' when (sck_sync(1) = '1' and sck_sync(2) = '0') else '0';

    -- Потоковый разбор пакета и верификация контрольной суммы
    process(clk, reset_n)
        variable computed_crc : std_logic_vector(7 downto 0);
    begin
        if reset_n = '0' then
            shift_reg <= (others => '0');
            bit_counter <= 0;
            reg_duty_cycle <= (others => '0');
            reg_charge_en <= '0';
            internal_crc_err <= '0';
            spi_miso <= 'Z';
        elsif rising_edge(clk) then
            
            if ss_n_sync(1) = '1' then
                bit_counter <= 0;
                spi_miso <= 'Z';
            else
                spi_miso <= shift_reg(23); -- Эхо-вывод старшего бита
                
                if sck_rising_edge = '1' then
                    shift_reg <= shift_reg(22 downto 0) & mosi_sync(1);
                    
                    if bit_counter = 23 then
                        bit_counter <= 0;
                        
                        -- Вычисление CRC-8 над первыми 16 информационными битами пакета [23:8]
                        computed_crc := calc_crc8_atm(shift_reg(23 downto 8));
                        
                        -- Сравнение вычисленного CRC с принятым из шины [7:0]
                        if computed_crc = shift_reg(7 downto 0) then
                            internal_crc_err <= '0'; -- Пакет валиден, помех нет
                            reg_charge_en    <= shift_reg(19); -- Извлечение бита активации заряда
                            
                            -- Валидация уставки duty_cycle во избежание сбоя генератора
                            if unsigned(shift_reg(18 downto 8)) < to_unsigned(PWM_PERIOD_CYCLES, 11) then
                                reg_duty_cycle <= shift_reg(18 downto 8);
                            else
                                reg_duty_cycle <= std_logic_vector(to_unsigned(PWM_PERIOD_CYCLES - DEAD_TIME_CYCLES, 11));
                            end if;
                        else
                            -- ОБНАРУЖЕНА ПОМЕХА: Команда игнорируется, взводится флаг ошибки для процессора ARM
                            internal_crc_err <= '1'; 
                        end if;
                    else
                        bit_counter <= bit_counter + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    PWM_CORE : interleaved_pwm_controller
        generic map (
            SYS_CLK_FREQ_HZ   => SYS_CLK_FREQ_HZ,
            PWM_PERIOD_CYCLES => PWM_PERIOD_CYCLES,
            DEAD_TIME_CYCLES  => DEAD_TIME_CYCLES
        )
        port map (
            clk             => clk,
            reset_n         => reset_n,
            duty_cycle      => reg_duty_cycle,
            charge_enable   => reg_charge_en,
            feeder_fault_n  => feeder_fault_n,
            phase1_gh       => phase1_gh,
            phase1_gl       => phase1_gl,
            phase2_gh       => phase2_gh,
            phase2_gl       => phase2_gl,
            system_locked   => system_locked
        );

end Behavioral;
