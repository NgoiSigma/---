#ifndef FEEDER_PROTECTION_HPP
#define FEEDER_PROTECTION_HPP

#include <cstdint>

class FeederProtection {
public:
    // Аппаратный порог тока (450 А для стандартного троллейбуса)
    static constexpr int32_t MAX_CURRENT_A = 450;
    
    // Максимально допустимая скорость нарастания тока (А/мс)
    // Превышение означает пробой изоляции или жесткое КЗ
    static constexpr int32_t MAX_DI_DT_A_MS = 50;

    FeederProtection() : m_last_current_a(0), m_is_tripped(false) {}

    // Метод вызывается таймером прерывания АЦП (каждую 1 мс)
    // Возвращает true, если зафиксирована авария и нужно рубить ШИМ
    bool processCurrentSample(int32_t current_a) {
        if (m_is_tripped) return true; // Защелка аварийного состояния

        // 1. Проверка на абсолютное превышение тока
        if (current_a >= MAX_CURRENT_A || current_a <= -MAX_CURRENT_A) {
            triggerTrip();
            return true;
        }

        // 2. Проверка производной (di/dt)
        // Абсолютное значение разницы между текущим и прошлым замером
        int32_t di_dt = current_a - m_last_current_a;
        if (di_dt < 0) di_dt = -di_dt; 

        if (di_dt >= MAX_DI_DT_A_MS) {
            triggerTrip();
            return true;
        }

        m_last_current_a = current_a;
        return false;
    }

    // Сброс защиты (вызывается диспетчером после устранения причин)
    void resetProtection() {
        m_is_tripped = false;
        m_last_current_a = 0;
    }

    bool isTripped() const {
        return m_is_tripped;
    }

private:
    void triggerTrip() {
        m_is_tripped = true;
        // Здесь в реальном коде также идет запись в регистр GPIO
        // для мгновенной блокировки ШИМ (сигнал feeder_fault_n на ПЛИС)
    }

    int32_t m_last_current_a;
    bool m_is_tripped;
};

#endif // FEEDER_PROTECTION_HPP
