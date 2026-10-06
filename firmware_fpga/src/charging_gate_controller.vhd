library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity charging_gate_controller is
    Generic (
        SYS_CLK_HZ : integer := 200_000_000;  -- Тактовая частота 200 МГц (период 5 нс)
        PWM_FREQ_HZ : integer := 150_000;     -- Частота ШИМ 150 кГц
        DEAD_TIME_NS : integer := 300         -- Dead-time 300 нс
    );
    Port (
        clk            : in  STD_LOGIC;
        rst_n          : in  STD_LOGIC;       -- Сброс (активный низкий)
        feeder_fault_n : in  STD_LOGIC;       -- Аппаратная отсечка при КЗ (активный низкий)
        duty_cycle     : in  unsigned(11 downto 0); -- Заполнение (0 - MAX_COUNT)
        pwm_high       : out STD_LOGIC;       -- Верхний ключ
        pwm_low        : out STD_LOGIC        -- Нижний ключ
    );
end charging_gate_controller;

architecture Behavioral of charging_gate_controller is
    constant MAX_COUNT  : integer := (SYS_CLK_HZ / PWM_FREQ_HZ) - 1; -- 1332
    constant DT_CYCLES  : integer := (DEAD_TIME_NS / (1_000_000_000 / SYS_CLK_HZ)); -- 60 тактов

    signal counter      : integer range 0 to MAX_COUNT := 0;
    signal pwm_ideal    : STD_LOGIC := '0';
begin

    -- Основной счетчик и формирование идеального ШИМ-сигнала
    process(clk, rst_n, feeder_fault_n)
    begin
        -- Асинхронная отсечка: реакция 5 нс (независимо от тактового сигнала)
        if rst_n = '0' or feeder_fault_n = '0' then
            counter <= 0;
            pwm_high <= '0';
            pwm_low <= '0';
            pwm_ideal <= '0';
        elsif rising_edge(clk) then
            if counter >= MAX_COUNT then
                counter <= 0;
            else
                counter <= counter + 1;
            end if;

            if counter < to_integer(duty_cycle) then
                pwm_ideal <= '1';
            else
                pwm_ideal <= '0';
            end if;

            -- Генерация Dead-Time (примитивная реализация счетчика задержки)
            -- Включение ключей сдвигается на DT_CYCLES тактов
            if pwm_ideal = '1' then
                if counter > DT_CYCLES and counter < (to_integer(duty_cycle) - 1) then
                    pwm_high <= '1';
                else
                    pwm_high <= '0';
                end if;
                pwm_low <= '0';
            else
                if counter > (to_integer(duty_cycle) + DT_CYCLES) then
                    pwm_low <= '1';
                else
                    pwm_low <= '0';
                end if;
                pwm_high <= '0';
            end if;
        end if;
    end process;

end Behavioral;
