#ifndef CAN_J1939_PARSER_HPP
#define CAN_J1939_PARSER_HPP

#include <cstdint>

// Стандартные PGN SAE J1939
constexpr uint32_t PGN_EEC1         = 61444; // Скорость вращения / базовая телеметрия
constexpr uint32_t PGN_HV_BATTERY   = 65110; // Параметры АКБ (включая SOC)
constexpr uint32_t PGN_VEHICLE_MASS = 65258; // Масса ТС (осевая нагрузка)

// Структура кадра raw CAN-интерфейса (совместимая с Linux SocketCAN)
struct CanFrame {
    uint32_t can_id;  // 29-битный расширенный ID
    uint8_t  can_dlc; // Длина данных (обычно 8 байт для J1939)
    uint8_t  data[8];
};

struct ExtractedCanData {
    float speed_kmh = 0.0f;
    float soc = 0.0f;
    uint32_t mass_kg = 0;
    bool speed_updated = false;
    bool soc_updated = false;
    bool mass_updated = false;
};

class CanJ1939Parser {
public:
    static uint32_t extract_pgn(uint32_t can_id) {
        // В J1939 PGN занимает с 9 по 24 бит 29-битного ID
        return (can_id >> 8) & 0x3FFFF;
    }

    bool parse_frame(const CanFrame& frame, ExtractedCanData& out_data) {
        if (frame.can_dlc < 8) return false;

        uint32_t pgn = extract_pgn(frame.can_id);

        switch (pgn) {
            case PGN_EEC1: {
                // Скорость ТС часто находится во 2-3 байтах (SPN 84)
                // Разрешение: 1/256 км/ч на бит, смещение: 0
                uint16_t raw_speed = (frame.data[2] << 8) | frame.data[1];
                out_data.speed_kmh = static_cast<float>(raw_speed) / 256.0f;
                out_data.speed_updated = true;
                return true;
            }
            case PGN_HV_BATTERY: {
                // SOC находится в 1-м байте (SPN 5796)
                // Разрешение: 0.4% на бит, смещение: 0
                out_data.soc = static_cast<float>(frame.data[0]) * 0.4f;
                out_data.soc_updated = true;
                return true;
            }
            case PGN_VEHICLE_MASS: {
                // Масса ТС находится в 3-4 байтах (SPN 174)
                // Разрешение: 2 кг на бит, смещение: 0
                uint16_t raw_mass = (frame.data[4] << 8) | frame.data[3];
                out_data.mass_kg = static_cast<uint32_t>(raw_mass) * 2;
                out_data.mass_updated = true;
                return true;
            }
            default:
                break;
        }
        return false;
    }
};

#endif // CAN_J1939_PARSER_HPP
