#ifndef FEEDER_PROTECTION_HPP
#define FEEDER_PROTECTION_HPP

#include <cstdint>

enum class FeederState : uint8_t {
    DISCONNECTED = 0,
    ISOLATED_FAULT = 1,
    NORMAL_CHARGING = 2
};

struct FeederMetrics {
    float current_amps;        // Текущий ток фидера
    float voltage_volts;       // Текущее напряжение на токосъемнике
    float delta_time_sec;      // Временной шаг измерения
};

class FeederProtection {
private:
    const float m_max_current_threshold = 450.0f; // Абсолютный предел тока (А)
    const float m_critical_didt         = 8000.0f; // Предельная скорость нарастания тока (А/сек)
    const float m_min_voltage_threshold = 400.0f;  // Просадка напряжения при КЗ (В)
    
    float m_last_current = 0.0f;
    bool m_breaker_tripped = false;

public:
    FeederProtection() = default;

    FeederState monitor_feeder(const FeederMetrics& metrics, bool contact_wires_connected) {
        if (!contact_wires_connected) {
            m_last_current = 0.0f;
            return FeederState::DISCONNECTED;
        }

        if (m_breaker_tripped) {
            return FeederState::ISOLATED_FAULT;
        }

        // Вычисление производной тока dI/dt (Ключевой маркер межвиткового или прямого КЗ)
        float di_dt = 0.0f;
        if (metrics.delta_time_sec > 0.0001f) { // Защита от деления на ноль в прерывании
            di_dt = (metrics.current_amps - m_last_current) / metrics.delta_time_sec;
        }
        m_last_current = metrics.current_amps;

        // Критерии фиксации короткого замыкания (Σ-FDL Ветвление противоречий среды)
        bool absolute_overcurrent = metrics.current_amps > m_max_current_threshold;
        bool di_dt_anomaly = di_dt > m_critical_didt;
        bool voltage_collapse = metrics.voltage_volts < m_min_voltage_threshold;

        if (absolute_overcurrent || (di_dt_anomaly && voltage_collapse)) {
            // АППАРАТНАЯ ОТСЕЧКА: немедленное срабатывание защитного реле
            m_breaker_tripped = true;
            return FeederState::ISOLATED_FAULT;
        }

        return FeederState::NORMAL_CHARGING;
    }

    void reset_breaker() { m_breaker_tripped = false; }
    bool is_breaker_tripped() const { return m_breaker_tripped; }
};

#endif // FEEDER_PROTECTION_HPP
