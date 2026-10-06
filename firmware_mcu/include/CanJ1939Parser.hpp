#ifndef CAN_J1939_PARSER_HPP
#define CAN_J1939_PARSER_HPP

#include <cstdint>

// Сырой кадр шины CAN J1939 (29-битный ID)
struct CanFrame29 {
    uint32_t id;         // 29-битный идентификатор
    uint8_t data[8];     // Полезная нагрузка
    uint8_t dlc;         // Data Length Code (обычно 8)
};

// Структура разобранной телеметрии для диспетчерской
struct TrolleybusTelemetry {
    uint16_t speed_kmh;      // Текущая скорость (км/ч)
    uint8_t soc_percent;     // Уровень заряда автономного хода (0-100%)
    uint32_t total_mass_kg;  // Общая масса (с учетом датчиков давления пневмоподвески)
    bool is_door_open;       // Состояние дверей (открыты/закрыты)
};

class CanJ1939Parser {
public:
    // PGN (Parameter Group Numbers) спецификации
    static constexpr uint32_t PGN_SPEED_MASS = 0x00FEF100;
    static constexpr uint32_t PGN_BMS_STATUS = 0x00FEE300;

    CanJ1939Parser() = default;

    // Zero-allocation парсер. Возвращает true, если пакет относится к нашему пулу PGN.
    bool parseFrame(const CanFrame29& frame, TrolleybusTelemetry& out_telemetry) const {
        // Извлекаем PGN из 29-битного ID (сдвиг и маска)
        uint32_t pgn = (frame.id >> 8) & 0x3FFFF;

        switch (pgn) {
            case (PGN_SPEED_MASS >> 8):
                // Байты 0-1: Скорость (разрешение 1/256 км/ч)
                out_telemetry.speed_kmh = ((frame.data[1] << 8) | frame.data[0]) / 256;
                
                // Байты 2-3: Масса (множитель 10 кг)
                out_telemetry.total_mass_kg = ((frame.data[3] << 8) | frame.data[2]) * 10;
                
                // Байт 4: Бит 0 - статус дверей
                out_telemetry.is_door_open = (frame.data[4] & 0x01) != 0;
                return true;

            case (PGN_BMS_STATUS >> 8):
                // Байт 0: SOC (State of Charge батареи)
                out_telemetry.soc_percent = frame.data[0];
                if (out_telemetry.soc_percent > 100) out_telemetry.soc_percent = 100;
                return true;

            default:
                // Пакет от стороннего ЭБУ (например, АБС), пропускаем
                return false;
        }
    }
};

#endif // CAN_J1939_PARSER_HPP
