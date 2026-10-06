#ifndef NOVEA_ATOM_ENGINE_HPP
#define NOVEA_ATOM_ENGINE_HPP

#include <cmath>
#include <cstdint>

// Ограничения статической памяти для встраиваемых платформ
constexpr size_t MAX_GEOFENCE_POINTS = 64;
constexpr size_t MAX_COMMANDS = 3;
constexpr size_t MAX_CMD_LEN = 96;

enum class VehicleClass : uint8_t {
    CLASS_A_WIRED = 0,      // Традиционные сеточные троллейбусы
    CLASS_B_AUTONOMOUS = 1  // Автономный ход с увеличенным запасом (ТАХ)
};

enum class SystemStatus : uint8_t {
    STATUS_OK = 0,
    STATUS_WARNING = 1,
    STATUS_CRITICAL = 2
};

struct GeoPoint {
    double latitude;
    double longitude;
};

// Входной массо-габаритный, пространственный и энергетический контур телеметрии
struct TelemetryFrame {
    char vehicle_id[16];
    VehicleClass v_class;
    GeoPoint coordinates;
    float speed_kmh;
    uint32_t passenger_count;       // Массо-габаритный контур (Δm)
    float soc;                      // State of Charge (%)
    float inertia_energy_j;         // Заряд кинетического инерцоида (Дж)
    bool contact_wires_connected;   // Статус штанг
    bool h_climate_active;          // Климат-контроль / отопление
};

// Фиксированный выходной буфер команд бортового терминала водителя
struct ResolutionResult {
    SystemStatus status;
    float k_sn;
    float estimated_range_km;       // Z_km
    uint8_t command_count;
    char commands[MAX_COMMANDS][MAX_CMD_LEN];
};

class NoveaAtomEngine {
private:
    GeoPoint m_wired_geofence[MAX_GEOFENCE_POINTS];
    size_t m_geofence_size;
    const float m_nr_base = 0.15f;  // Базовый абстрактно-необходимый норматив (кВт*ч / ФЕ)

    bool check_geofence(const GeoPoint& coords) const;
    float calculate_k_sn(const TelemetryFrame& frame) const;
    void copy_string(char* dest, const char* src, size_t max_len) const;

public:
    NoveaAtomEngine();
    bool initialize_geofence(const GeoPoint* points, size_t size);
    ResolutionResult resolve_contradictions(const TelemetryFrame& frame) const;
};

#endif // NOVEA_ATOM_ENGINE_HPP
