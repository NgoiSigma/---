library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity interleaved_pwm_controller is
    Generic (
        SYS_CLK_FREQ_HZ   : integer := 200000000; -- 200 МГц
        PWM_PERIOD_CYCLES : integer := 1333;      -- 150 кГц
        DEAD_TIME_CYCLES  : integer := 60         -- 300 нс
    );
    Port (
        clk             : in  STD_LOGIC;
        reset_n         : in  STD_LOGIC;
        
        duty_cycle      : in  STD_LOGIC_VECTOR(10 downto 0);
        charge_enable   : in  STD_LOGIC;
        feeder_fault_n  : in  STD_LOGIC;
        
        -- Выходы Фазы 1
        phase1_gh       : out STD_LOGIC;
        phase1_gl       : out STD_LOGIC;
        -- Выходы Фазы 2 (Сдвиг 180 градусов)
        phase2_gh       : out STD_LOGIC;
        phase2_gl       : out STD_LOGIC;
        
        system_locked   : out STD_LOGIC
    );
end interleaved_pwm_controller;

architecture Behavioral of interleaved_pwm_controller is
    -- Индивидуальные счетчики периодов для обеспечения сдвига фаз
    signal count_p1        : unsigned(10 downto 0) := (others => '0');
    signal count_p2        : unsigned(10 downto 0) := to_unsigned(666, 10); -- Инициализация сдвига (1333 / 2)
    
    signal active_p2       : STD_LOGIC := '0';
    signal global_lock     : STD_LOGIC := '0';
begin

    system_locked <= global_lock;

    -- Процесс генерации импульсов для ФАЗЫ 1
    process(clk, reset_n)
        variable current_duty : unsigned(10 downto 0);
    begin
        if reset_n = '0' then
            count_p1 <= (others => '0');
            phase1_gh <= '0';
            phase1_gl <= '0';
            active_p2 <= '0';
        elsif rising_edge(clk) then
            if feeder_fault_n = '0' or global_lock = '1' then
                phase1_gh <= '0';
                phase1_gl <= '0';
            else
                current_duty := unsigned(duty_cycle);
                
                -- Управление инкрементом основного счетчика
                if count_p1 >= (PWM_PERIOD_CYCLES - 1) then
                    count_p1 <= (others => '0');
                else
                    count_p1 <= count_p1 + 1;
                end if;
                
                -- Активация запуска второй фазы при достижении середины периода первой фазы
                if count_p1 = to_unsigned(666, 10) then
                    active_p2 <= '1';
                end if;

                -- Логика формирования ШИМ с учетом Мертвого Времени (Phase 1)
                if charge_enable = '1' then
                    if count_p1 < current_duty then
                        phase1_gh <= '1';
                        phase1_gl <= '0';
                    elsif count_p1 >= current_duty and count_p1 < (current_duty + DEAD_TIME_CYCLES) then
                        phase1_gh <= '0';
                        phase1_gl <= '0';
                    else
                        phase1_gh <= '0';
                        phase1_gl <= '1';
                    end if;
                else
                    phase1_gh <= '0';
                    phase1_gl <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Процесс генерации импульсов для ФАЗЫ 2 (Сдвиг 180 градусов)
    process(clk, reset_n)
        variable current_duty : unsigned(10 downto 0);
    begin
        if reset_n = '0' then
            count_p2 <= (others => '0');
            phase2_gh <= '0';
            phase2_gl <= '0';
        elsif rising_edge(clk) then
            if feeder_fault_n = '0' or global_lock = '1' then
                phase2_gh <= '0';
                phase2_gl <= '0';
            else
                current_duty := unsigned(duty_cycle);
                
                if active_p2 = '1' then
                    if count_p2 >= (PWM_PERIOD_CYCLES - 1) then
                        count_p2 <= (others => '0');
                    else
                        count_p2 <= count_p2 + 1;
                    end if;
                    
                    -- Логика формирования ШИМ с учетом Мертвого Времени (Phase 2)
                    if charge_enable = '1' then
                        if count_p2 < current_duty then
                            phase2_gh <= '1';
                            phase2_gl <= '0';
                        elsif count_p2 >= current_duty and count_p2 < (current_duty + DEAD_TIME_CYCLES) then
                            phase2_gh <= '0';
                            phase2_gl <= '0';
                        else
                            phase2_gh <= '0';
                            phase2_gl <= '1';
                        end if;
                    else
                        phase2_gh <= '0';
                        phase2_gl <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Аппаратная защитная защелка блокировки при аварии КЗ
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            global_lock <= '0';
        elsif rising_edge(clk) then
            if feeder_fault_n = '0' then
                global_lock <= '1'; -- Аварийный триггер взведен
            elsif charge_enable = '0' then
                global_lock <= '0'; -- Сброс триггера только при программной деактивации заряда
            end if;
        end if;
    end process;

end Behavioral;
