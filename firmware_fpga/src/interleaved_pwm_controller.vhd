library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity interleaved_pwm_controller is
    Port (
        clk            : in  STD_LOGIC;
        rst_n          : in  STD_LOGIC;
        feeder_fault_n : in  STD_LOGIC;
        global_duty    : in  unsigned(11 downto 0);
        
        -- Выходы фазы 1
        ph1_high       : out STD_LOGIC;
        ph1_low        : out STD_LOGIC;
        
        -- Выходы фазы 2
        ph2_high       : out STD_LOGIC;
        ph2_low        : out STD_LOGIC
    );
end interleaved_pwm_controller;

architecture Structural of interleaved_pwm_controller is
    constant SYS_CLK_HZ : integer := 200_000_000;
    constant PWM_FREQ_HZ : integer := 150_000;
    constant HALF_PERIOD : integer := (SYS_CLK_HZ / PWM_FREQ_HZ) / 2; -- 666 тактов для сдвига 180°

    signal ph2_duty_delayed : unsigned(11 downto 0) := (others => '0');
    signal phase_counter    : integer range 0 to (SYS_CLK_HZ / PWM_FREQ_HZ) - 1 := 0;
begin

    -- Фаза 1 (базовая)
    Phase1_Inst: entity work.charging_gate_controller
        port map (
            clk => clk,
            rst_n => rst_n,
            feeder_fault_n => feeder_fault_n,
            duty_cycle => global_duty,
            pwm_high => ph1_high,
            pwm_low => ph1_low
        );

    -- Процесс сдвига фазы для Фазы 2
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                phase_counter <= 0;
                ph2_duty_delayed <= (others => '0');
            else
                if phase_counter >= ((SYS_CLK_HZ / PWM_FREQ_HZ) - 1) then
                    phase_counter <= 0;
                else
                    phase_counter <= phase_counter + 1;
                end if;
                
                -- Защелкиваем значение duty cycle с задержкой в полпериода
                if phase_counter = HALF_PERIOD then
                    ph2_duty_delayed <= global_duty;
                end if;
            end if;
        end if;
    end process;

    -- Фаза 2 (сдвинутая на 180 градусов)
    Phase2_Inst: entity work.charging_gate_controller
        port map (
            clk => clk,
            rst_n => rst_n,
            feeder_fault_n => feeder_fault_n,
            duty_cycle => ph2_duty_delayed,
            pwm_high => ph2_high,
            pwm_low => ph2_low
        );

end Structural;
