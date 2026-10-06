#ifndef INERTER_DIAGNOSTICS_HPP
#define INERTER_DIAGNOSTICS_HPP

#include <cmath>
#include <cstdint>

enum class InerterState : uint8_t {
    OFFLINE    = 0,
    CHARGING   = 1,
    DISCHARGING = 2,
    FAULT      = 3
};

struct InerterSensors {
    float flywheel_rpm;          // Обороты маховика в минуту
    float calculated_energy_j;   // Энергия, заявленная бортовым контроллером
    float coil_temperature_c;    // Температура обмоток муфты рекуперации
    float bus_voltage;           // Напряжение внутренней шины инерцоида
};

class InerterDiagnostics {
private:
    const float m_moment_of_inertia = 2.5f; // Паспортный момент инерции маховика (кг*м²)
    const float m_max_allowed_temp  = 95.0f; // Критическая температура обмоток (°C)
    bool m_isolation_relay_tripped  = false;

public:
    InerterDiagnostics() = default;

    InerterState perform_diagnostic(const InerterSensors& sensors, bool& out_fault_flag) {
        out_fault_flag = false;

        // 1. Проверка температурного контура безопасности
        if (sensors.coil_temperature_c > m_max_allowed_temp) {
            m_isolation_relay_tripped = true;
            out_fault_flag = true;
            return InerterState::FAULT;
        }

        // 2. Верификация закона сохранения энергии (Поиск проскальзывания или утечек)
        // E = 0.5 * I * w^2 ; w = (RPM * 2 * pi) / 60
        float omega = (sensors.flywheel_rpm * 2.0f * 3.141592f) / 60.0f;
        float physical_energy = 0.5f * m_moment_of_inertia * omega * omega;

        // Допускаем погрешность преобразования не более 7%
        float energy_deviation = std::abs(physical_energy - sensors.calculated_energy_j);
        if (sensors.flywheel_rpm > 100.0f && (energy_deviation / physical_energy) > 0.07f) {
            m_isolation_relay_tripped = true;
            out_fault_flag = true;
            return InerterState::FAULT;
        }

        // 3. Определение текущего эксплуатационного статуса
        m_isolation_relay_tripped = false;
        if (sensors.flywheel_rpm < 50.0f) {
            return InerterState::OFFLINE;
        }
        
        // Проверка вектора движения энергии по напряжению шины
        if (sensors.bus_voltage > 650.0f) return InerterState::CHARGING;
        if (sensors.bus_voltage < 550.0f && sensors.bus_voltage > 10.0f) return InerterState::DISCHARGING;

        return InerterState::OFFLINE;
    }

    bool is_isolated() const { return m_isolation_relay_tripped; }
};

#endif // INERTER_DIAGNOSTICS_HPP
