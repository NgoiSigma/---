library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity charging_gate_controller is
    Generic (
        -- Частота тактирования ПЛИС 200 МГц (период 5 нс)
        -- Для частоты ШИМ 150 кГц период равен: 200 МГц / 150 кГц = 1333 такта
        SYS_CLK_FREQ_HZ : integer := 200000000;
        PWM_PERIOD_CYCLES : integer := 1333;
        -- Мертвое время (Dead-Time) = 300 нс (300 / 5 = 60 тактов)
        DEAD_TIME_CYCLES : integer := 60
    );
    Port (
        clk             : in  STD_LOGIC; -- Системный тактовый сигнал 200 МГц
        reset_n         : in  STD_LOGIC; -- Асинхронный сброс (активный низкий)
        
        -- Управляющие сигналы
        duty_cycle      : in  STD_LOGIC_VECTOR(10 downto 0); -- Коэффициент заполнения (0..1333)
        charge_enable   : in  STD_LOGIC; -- Разрешение заряда от центрального процессора
        feeder_fault_n  : in  STD_LOGIC; -- Аппаратное прерывание КЗ от компаратора (активный низкий)
        
        -- Выходы на драйверы затворов (полумостовая схема)
        gate_high       : out STD_LOGIC; -- Верхнее плечо преобразователя
        gate_low        : out STD_LOGIC  -- Нижнее плечо преобразователя
    );
end charging_gate_controller;

architecture Behavioral of charging_gate_controller is
    signal pwm_counter     : unsigned(10 downto 0) := (others => '0');
    signal internal_gh     : STD_LOGIC := '0';
    signal internal_gl     : STD_LOGIC := '0';
    signal dead_time_cnt   : integer range 0 to DEAD_TIME_CYCLES := 0;
    
    type state_type is (IDLE, ACTIVE_HIGH, DEADZONE_LOW, ACTIVE_LOW, DEADZONE_HIGH, EMERGENCY_LOCK);
    signal current_state : state_type := IDLE;
begin

    -- Аппаратный автомат состояний генератора ШИМ с контролем сквозного тока
    process(clk, reset_n)
        variable current_duty : unsigned(10 downto 0);
    begin
        if reset_n = '0' then
            pwm_counter <= (others => '0');
            internal_gh <= '0';
            internal_gl <= '0';
            current_state <= IDLE;
        elsif rising_edge(clk) then
            
            -- Высший приоритет: Мгновенное аппаратное защитное отключение (время реакции 5 нс)
            if feeder_fault_n = '0' then
                internal_gh <= '0';
                internal_gl <= '0';
                current_state <= EMERGENCY_LOCK;
            else
                current_duty := unsigned(duty_cycle);
                
                case current_state is
                    when EMERGENCY_LOCK =>
                        internal_gh <= '0';
                        internal_gl <= '0';
                        if charge_enable = '0' then 
                            current_state <= IDLE; -- Выход из блокировки только после сброса команды
                        end if;

                    when IDLE =>
                        internal_gh <= '0';
                        internal_gl <= '0';
                        pwm_counter <= (others => '0');
                        if charge_enable = '1' then
                            current_state <= ACTIVE_HIGH;
                        end if;

                    when ACTIVE_HIGH =>
                        if pwm_counter >= current_duty then
                            internal_gh <= '0'; -- Выключение верхнего плеча
                            dead_time_cnt <= 0;
                            current_state <= DEADZONE_LOW;
                        else
                            internal_gh <= '1';
                            internal_gl <= '0';
                            pwm_counter <= pwm_counter + 1;
                        end if;

                    when DEADZONE_LOW =>
                        internal_gh <= '0';
                        internal_gl <= '0';
                        pwm_counter <= pwm_counter + 1;
                        if dead_time_cnt >= DEAD_TIME_CYCLES - 1 then
                            current_state <= ACTIVE_LOW;
                        else
                            dead_time_cnt <= dead_time_cnt + 1;
                        end if;

                    when ACTIVE_LOW =>
                        if pwm_counter >= (PWM_PERIOD_CYCLES - 1) then
                            internal_gl <= '0'; -- Выключение нижнего плеча в конце периода
                            pwm_counter <= (others => '0');
                            dead_time_cnt <= 0;
                            current_state <= DEADZONE_HIGH;
                        else
                            internal_gh <= '0';
                            internal_gl <= '1';
                            pwm_counter <= pwm_counter + 1;
                        end if;

                    when DEADZONE_HIGH =>
                        internal_gh <= '0';
                        internal_gl <= '0';
                        if dead_time_cnt >= DEAD_TIME_CYCLES - 1 then
                            if charge_enable = '1' then
                                current_state <= ACTIVE_HIGH;
                            else
                                current_state <= IDLE;
                            end if;
                        else
                            dead_time_cnt <= dead_time_cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- Вывод очищенных сигналов управления на физические выводы портов ПЛИС
    gate_high <= internal_gh;
    gate_low  <= internal_gl;

end Behavioral;
