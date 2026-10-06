library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_pwm_bridge is
    Generic (
        SYS_CLK_FREQ_HZ   : integer := 200000000; -- 200 МГц
        PWM_PERIOD_CYCLES : integer := 1333;      -- 150 кГц
        DEAD_TIME_CYCLES  : integer := 60         -- 300 нс
    );
    Port (
        -- Системные сигналы ПЛИС
        clk             : in  STD_LOGIC;
        reset_n         : in  STD_LOGIC;
        
        -- Физические линии шины SPI от центрального процессора
        spi_sck         : in  STD_LOGIC; -- Тактовый сигнал SPI
        spi_ss_n        : in  STD_LOGIC; -- Выбор ведомого (Active Low)
        spi_mosi        : in  STD_LOGIC; -- Вход данных
        spi_miso        : out STD_LOGIC; -- Выход данных (для эхо-контроля)
        
        -- Аппаратные сигналы силовой защиты
        feeder_fault_n  : in  STD_LOGIC; -- Аварийный сигнал КЗ
        
        -- Выходные силовые импульсы ШИМ (интерливинг каскад)
        phase1_gh       : out STD_LOGIC;
        phase1_gl       : out STD_LOGIC;
        phase2_gh       : out STD_LOGIC;
        phase2_gl       : out STD_LOGIC;
        
        system_locked   : out STD_LOGIC
    );
end spi_pwm_bridge;

architecture Behavioral of spi_pwm_bridge is

    -- Компонент двухфазного ШИМ-контроллера, разработанный на предыдущем этапе
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

    -- Сигналы SPI-регистра сдвига
    signal bit_counter     : integer range 0 to 15 := 0;
    signal shift_reg       : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    signal data_ready      : STD_LOGIC := '0';
    
    -- Регистры синхронизации SPI линий для подавления метастабильности
    signal sck_sync        : STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
    signal ss_n_sync       : STD_LOGIC_VECTOR(1 downto 0) := (others => '1');
    signal mosi_sync       : STD_LOGIC_VECTOR(1 downto 0) := (others => '0');
    
    -- Управляющие регистры, обновляемые по завершении SPI-транзакции
    signal reg_duty_cycle  : STD_LOGIC_VECTOR(10 downto 0) := (others => '0');
    signal reg_charge_en   : STD_LOGIC := '0';

begin

    -- Синхронизация асинхронных внешних линий SPI с тактовой частотой ПЛИС (200 МГц)
    process(clk)
    begin
        if rising_edge(clk) then
            sck_sync  <= sck_sync(1 downto 0) & spi_sck;
            ss_n_sync <= ss_n_sync(0) & spi_ss_n;
            mosi_sync <= mosi_sync(0) & spi_mosi;
        end if;
    end process;

    -- Выделение фронтов сигналов
    -- SPI Mode 0: чтение бита по переднему (нарастающему) фронту SCK
    sck_rising_edge <= '1' when (sck_sync(1) = '1' and sck_sync(2) = '0') else '0';

    -- Автомат захвата данных шины SPI
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            shift_reg <= (others => '0');
            bit_counter <= 0;
            reg_duty_cycle <= (others => '0');
            reg_charge_en <= '0';
            spi_miso <= 'Z';
        elsif rising_edge(clk) then
            
            if ss_n_sync(1) = '1' then
                -- Преобразователь не выбран: сброс счетчика бит
                bit_counter <= 0;
                spi_miso <= 'Z';
            else
                spi_miso <= shift_reg(15); -- Вывод старшего бита (эхо)
                
                if sck_rising_edge = '1' then
                    -- Задвигаем бит данных с линии MOSI
                    shift_reg <= shift_reg(14 downto 0) & mosi_sync(1);
                    
                    if bit_counter = 15 then
                        bit_counter <= 0;
                        -- Пакет принят полностью: парсинг командного слова
                        reg_charge_en  <= shift_reg(11); -- 11-й бит: Флаг разрешения работы
                        
                        -- Безопасное ограничение duty_cycle: значение не должно превышать период ШИМ
                        if unsigned(shift_reg(10 downto 0)) < to_unsigned(PWM_PERIOD_CYCLES, 11) then
                            reg_duty_cycle <= shift_reg(10 downto 0);
                        else
                            reg_duty_cycle <= std_logic_vector(to_unsigned(PWM_PERIOD_CYCLES - DEAD_TIME_CYCLES, 11));
                        end if;
                    else
                        bit_counter <= bit_counter + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Инициализация и привязка портов интерливинг-контроллера ШИМ
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
