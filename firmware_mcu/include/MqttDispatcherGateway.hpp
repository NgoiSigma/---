#ifndef MQTT_DISPATCHER_GATEWAY_HPP
#define MQTT_DISPATCHER_GATEWAY_HPP

#include <cstdint>
#include <cstdio>
#include "CanJ1939Parser.hpp"

class MqttDispatcherGateway {
public:
    // Максимальный размер MQTT-пакета (ограничен для экономии RAM)
    static constexpr size_t MAX_PAYLOAD_SIZE = 256;

    MqttDispatcherGateway() = default;

    // Формирование JSON-строки в предоставленный статический буфер
    // Возвращает длину сгенерированной строки
    size_t buildTelemetryPayload(char* buffer, size_t buffer_size, 
                                 uint32_t device_id, 
                                 const TrolleybusTelemetry& t, 
                                 uint16_t ksn_value) const {
        if (buffer == nullptr || buffer_size == 0) return 0;

        // Строгая генерация без выделения памяти в куче
        // Используем snprintf для защиты от переполнения буфера (Buffer Overflow)
        int written = snprintf(buffer, buffer_size,
            "{\"dev_id\":%u,\"spd_kmh\":%u,\"soc\":%u,\"mass_kg\":%u,\"doors\":%d,\"k_sn\":%u}",
            device_id,
            t.speed_kmh,
            t.soc_percent,
            t.total_mass_kg,
            t.is_door_open ? 1 : 0,
            ksn_value
        );

        if (written < 0 || static_cast<size_t>(written) >= buffer_size) {
            // Ошибка форматирования или буфер слишком мал (строка усечена)
            buffer[buffer_size - 1] = '\0';
            return buffer_size - 1;
        }

        return static_cast<size_t>(written);
    }
};

#endif // MQTT_DISPATCHER_GATEWAY_HPP
