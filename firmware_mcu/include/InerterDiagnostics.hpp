#ifndef INERTER_DIAGNOSTICS_HPP
#define INERTER_DIAGNOSTICS_HPP

#include <cstdint>

class InerterDiagnostics {
public:
    // Момент инерции маховика I (кг*м^2), умноженный на 1000 для целочисленной математики
    static constexpr uint32_t INERTIA_MOMENT_E3 = 25000; // Реальное значение: 25.0 кг*м^2
    
    // Допустимая дельта потерь энергии между замерами (Дж)
    static constexpr uint32_t MAX_ENERGY_LOSS_TOLERANCE_J = 500;

    InerterDiagnostics() : m_last_energy_j(0) {}

    // Расчет текущей энергии и проверка на аномальные потери
    // omega_rad_s - угловая скорость вращения маховика (рад/с)
    bool verifyEnergyState(uint16_t omega_rad_s, uint32_t& out_current_energy_j) {
        // E = (I * w^2) / 2
        // Поскольку INERTIA_MOMENT_E3 увеличен в 1000 раз, делим результат на 2000
        uint64_t omega_sq = static_cast<uint64_t>(omega_rad_s) * omega_rad_s;
        uint64_t energy_raw = (INERTIA_MOMENT_E3 * omega_sq) / 2000;
        
        out_current_energy_j = static_cast<uint32_t>(energy_raw);

        bool is_anomaly_detected = false;

        // Если энергия упала резче, чем ожидается при естественном выбеге
        if (m_last_energy_j > out_current_energy_j) {
            uint32_t energy_delta = m_last_energy_j - out_current_energy_j;
            if (energy_delta > MAX_ENERGY_LOSS_TOLERANCE_J) {
                is_anomaly_detected = true; 
            }
        }

        m_last_energy_j = out_current_energy_j;
        return is_anomaly_detected;
    }

private:
    uint32_t m_last_energy_j;
};

#endif // INERTER_DIAGNOSTICS_HPP
