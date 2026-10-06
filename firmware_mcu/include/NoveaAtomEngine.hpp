#ifndef NOVEA_ATOM_ENGINE_HPP
#define NOVEA_ATOM_ENGINE_HPP

#include <cstdint>

// Структура геокоординат в формате fixed-point (целые числа, умноженные на 10^7)
// Гарантирует точность без использования float/double
struct GeoPoint {
    int32_t lat_e7; 
    int32_t lon_e7; 
};

class NoveaAtomEngine {
public:
    // Базовая масса транспортного средства передается при инициализации
    constexpr explicit NoveaAtomEngine(uint32_t base_mass_kg) 
        : m_base_mass(base_mass_kg) {}

    // Вычисление квадрата расстояния для геометрических проверок 
    // Заменяет std::sqrt, что критично для производительности MCU
    static uint64_t calculateSquaredDistance(const GeoPoint& p1, const GeoPoint& p2) {
        int64_t dLat = static_cast<int64_t>(p1.lat_e7) - p2.lat_e7;
        int64_t dLon = static_cast<int64_t>(p1.lon_e7) - p2.lon_e7;
        return (dLat * dLat) + (dLon * dLon);
    }

    // Вычисление коэффициента K_sn (норма энергопотребления/сложности)
    // Адаптировано под параметры тягового расчета троллейбусов
    uint16_t computeKsn(uint16_t current_speed_kmh, uint32_t passengers_mass_kg, uint64_t sq_distance) const {
        if (current_speed_kmh == 0) return 0; // Защита от деления на ноль на остановках
        
        uint32_t total_mass = m_base_mass + passengers_mass_kg;
        
        // Нормировочное уравнение (упрощенная fixed-point адаптация)
        // Битовый сдвиг >> 14 применяется для масштабирования больших квадратов дистанции
        uint64_t ksn_raw = (static_cast<uint64_t>(total_mass) * (sq_distance >> 14)) / current_speed_kmh;
        
        // Clamping (ограничение) результата до размерности uint16_t
        return (ksn_raw > 65535) ? 65535 : static_cast<uint16_t>(ksn_raw);
    }

private:
    uint32_t m_base_mass;
};

#endif // NOVEA_ATOM_ENGINE_HPP
