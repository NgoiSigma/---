#ifndef MQTT_DISPATCHER_GATEWAY_HPP
#define MQTT_DISPATCHER_GATEWAY_HPP

#include <cstdio>
#include <cstdint>

constexpr char NIKOLAEV_DISPATCH_SERVER[] = "tcp://tracking.mkrada.gov.ua:1883";
constexpr char TOPIC_FORMAT[] = "nikolaev/electrotrans/vehicles/%d/telemetry";

struct OutboundPayload {
    int vehicle_id;
    float speed;
    float soc;
    uint32_t mass;
    float k_sn;
    float range_left;
    bool inerter_fault;
};

class MqttDispatcherGateway {
private:
    char m_json_buffer[512];
    char m_topic_buffer[128];

public:
    MqttDispatcherGateway() {
        m_json_buffer[0] = '\0';
        m_topic_buffer[0] = '\0';
    }

    // Маршаллинг данных без использования динамических строк std::string
    const char* serialize_payload(const OutboundPayload& payload) {
        std::snprintf(m_json_buffer, sizeof(m_json_buffer),
            "{\"v_id\":%d,\"spd\":%.2f,\"soc\":%.1f,\"mass\":%u,\"ksn\":%.3f,\"rng\":%.1f,\"inf\":%s}",
            payload.vehicle_id,
            payload.speed,
            payload.soc,
            payload.mass,
            payload.k_sn,
            payload.range_left,
            payload.inerter_fault ? "true" : "false"
        );
        return m_json_buffer;
    }

    const char* generate_topic(int vehicle_id) {
        std::snprintf(m_topic_buffer, sizeof(m_topic_buffer), TOPIC_FORMAT, vehicle_id);
        return m_topic_buffer;
    }

    bool transmit_via_gsm(int vehicle_id, const OutboundPayload& payload) {
        const char* topic = generate_topic(vehicle_id);
        const char* message = serialize_payload(payload);

        // Имитация физического уровня стека MQTT/GSM-модема
        std::printf("[GSM/MQTT AT L3] Подключение к %s...\n", NIKOLAEV_DISPATCH_SERVER);
        std::printf("[GSM/MQTT AT L3] Публикация в Топик: %s\n", topic);
        std::printf("[GSM/MQTT AT L3] Данные пакета: %s\n", message);
        
        // В реальном коде: return (mqtt_client.publish(topic, message) == MQTT_SUCCESS);
        return true;
    }
};

#endif // MQTT_DISPATCHER_GATEWAY_HPP
