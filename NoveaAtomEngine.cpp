#include "NoveaAtomEngine.hpp"

NoveaAtomEngine::NoveaAtomEngine() : m_geofence_size(0) {}

bool NoveaAtomEngine::initialize_geofence(const GeoPoint* points, size_t size) {
    if (size > MAX_GEOFENCE_POINTS) return false;
    for (size_t i = 0; i < size; ++i) {
        m_wired_geofence[i] = points[i];
    }
    m_geofence_size = size;
    return true;
}

void NoveaAtomEngine::copy_string(char* dest, const char* src, size_t max_len) const {
    size_t i = 0;
    for (; i < max_len - 1 && src[i] != '\0'; ++i) {
        dest[i] = src[i];
    }
    dest[i] = '\0';
}

bool NoveaAtomEngine::check_geofence(const GeoPoint& coords) const {
    // Детерминированный радиус-фильтр геозоны (допустимое отклонение ~5 метров)
    constexpr double APPROX_5_METERS_DEG = 0.00005;
    for (size_t i = 0; i < m_geofence_size; ++i) {
        double d_lat = coords.latitude - m_wired_geofence[i].latitude;
        double d_lon = coords.longitude - m_wired_geofence[i].longitude;
        // Квадрат Евклидова расстояния для исключения тяжелой операции sqrt на MCU
        if ((d_lat * d_lat + d_lon * d_lon) < (APPROX_5_METERS_DEG * APPROX_5_METERS_DEG)) {
            return true;
        }
    }
    return false;
}

float NoveaAtomEngine::calculate_k_sn(const TelemetryFrame& frame) const {
    constexpr float BASE_MASS_KG = 12000.0f; // Пустой троллейбус
    constexpr float AVG_PASSENGER_MASS_KG = 75.0f;
    
    // Массо-габаритный контур полезной нагрузки (Δm)
    float total_mass = BASE_MASS_KG + (static_cast<float>(frame.passenger_count) * AVG_PASSENGER_MASS_KG);
    
    // Перевод скорости из км/ч в м/с
    float speed_ms = frame.speed_kmh / 3.6f;
    
    // Динамическая кинетическая составляющая расхода энергии (в кВт*ч)
    float kinetic_factor = (0.5f * total_mass * speed_ms * speed_ms) / 3600000.0f;
    
    // Расход вспомогательных систем (климат-контроль)
    float climate_load = frame.h_climate_active ? 0.05f : 0.01f;
    
    float denominator = frame.passenger_count > 0 ? static_cast<float>(frame.passenger_count) : 1.0f;
    float nr_fact = (kinetic_factor + climate_load) / denominator;
    
    if (nr_fact <= 0.0f) return 1.0f;
    
    // Вычисление коэффициента совершенствования K_sn = NR_база / NR_факт
    return m_nr_base / nr_fact;
}

ResolutionResult NoveaAtomEngine::resolve_contradictions(const TelemetryFrame& frame) const {
    ResolutionResult result{};
    result.status = SystemStatus::STATUS_OK;
    result.k_sn = calculate_k_sn(frame);
    result.estimated_range_km = 0.0f;
    result.command_count = 0;

    bool in_network = check_geofence(frame.coordinates);

    // --- ЛОГИКА ВЕТВЛЕНИЯ Σ-FDL ДЛЯ РАЗЛИЧНЫХ КЛАССОВ МАШИН ---
    
    if (frame.v_class == VehicleClass::CLASS_A_WIRED) {
        // Проверка Класса А: Строгое соответствие среде обитания контактной сети
        if (!in_network && frame.contact_wires_connected) {
            result.status = SystemStatus::STATUS_CRITICAL;
            copy_string(result.commands[result.command_count++], 
                        "EMERGENCY_BRAKE: Выход из среды обитания! Риск обрыва штанг.", MAX_CMD_LEN);
        } else {
            copy_string(result.commands[result.command_count++], 
                        "STANDARD_WIRED_MODE: Штатное потребление тока из сети.", MAX_CMD_LEN);
        }
    } 
    else if (frame.v_class == VehicleClass::CLASS_B_AUTONOMOUS) {
        // Проверка Класса B: Работа под сетью или на автономном ходу (ТАХ)
        if (!frame.contact_wires_connected) {
            // Расчет динамической квазинормы автономного запаса хода Z_km = f(SOC, Δm, P_klima, E_kin)
            float consumption_rate = 1.0f + (static_cast<float>(frame.passenger_count) * 0.02f) 
                                     + (frame.h_climate_active ? 0.15f : 0.0f);
            
            // Аппаратная стабилизация: интеграция инерцоида (активация кинетического демпфера)
            if (frame.inertia_energy_j > 100000.0f) {
                consumption_rate -= 0.25f; // Снижение падения заряда за счет кинетической отдачи
            }
            
            float safe_denominator = consumption_rate > 0.1f ? consumption_rate : 0.1f;
            result.estimated_range_km = (frame.soc / safe_denominator) * 0.4f;

            // Разрешение противоречия при дефиците емкости батареи (критический порог < 30%)
            if (frame.soc < 30.0f) {
                result.status = SystemStatus::STATUS_WARNING;
                if (frame.inertia_energy_j > 0.0f) {
                    copy_string(result.commands[result.command_count++], 
                                "ACTIVATE_INERTIOID_DISCHARGE: Кинетическая стабилизация пуска.", MAX_CMD_LEN);
                }
                copy_string(result.commands[result.command_count++], 
                            "CORRECT_SPEED_PROFILE: Коррекция скорости до точки контакта.", MAX_CMD_LEN);
            } else {
                copy_string(result.commands[result.command_count++], 
                            "AUTONOMOUS_WALK_MODE: Движение на автономном ходу.", MAX_CMD_LEN);
            }
        } else {
            // Возврат в геозону: Синхронное лимитирование тока подстанции при зарядке в движении
            copy_string(result.commands[result.command_count++], 
                        "DYNAMIC_CHARGING_ACTIVE: Ограничение фидерного тока.", MAX_CMD_LEN);
        }
    }

    return result;
}
