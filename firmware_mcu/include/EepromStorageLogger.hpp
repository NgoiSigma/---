#ifndef EEPROM_STORAGE_LOGGER_HPP
#define EEPROM_STORAGE_LOGGER_HPP

#include <cstdint>
#include <atomic>

// Структура записи лога (8 байт для оптимального выравнивания)
struct LogEntry {
    uint32_t timestamp_s;  // Время события (Unix epoch или аптайм)
    uint16_t event_code;   // Код ошибки (например, 0x7E, 0x3F)
    uint16_t value;        // Зафиксированное значение (ток, температура и т.д.)
};

class EepromStorageLogger {
public:
    static constexpr uint32_t MAX_ENTRIES = 128;

    EepromStorageLogger() : m_head(0), m_tail(0) {}

    // Запись события (безопасно для вызова из ISR)
    // Использует std::memory_order_relaxed для минимального оверхеда
    void logEvent(uint32_t timestamp, uint16_t code, uint16_t val) {
        uint32_t current_head = m_head.load(std::memory_order_relaxed);
        uint32_t next_head = (current_head + 1) % MAX_ENTRIES;

        // Перезаписываем старые данные при переполнении (кольцевой механизм)
        m_buffer[current_head] = {timestamp, code, val};
        m_head.store(next_head, std::memory_order_release);

        // Если догнали хвост, сдвигаем его (теряем самую старую запись)
        if (next_head == m_tail.load(std::memory_order_acquire)) {
            m_tail.store((next_head + 1) % MAX_ENTRIES, std::memory_order_release);
        }
    }

    // Чтение последних событий для отправки в диспетчерскую через MQTT
    bool readEvent(LogEntry& out_entry) {
        uint32_t current_tail = m_tail.load(std::memory_order_relaxed);
        
        if (current_tail == m_head.load(std::memory_order_acquire)) {
            return false; // Буфер пуст
        }

        out_entry = m_buffer[current_tail];
        m_tail.store((current_tail + 1) % MAX_ENTRIES, std::memory_order_release);
        return true;
    }

private:
    // Размещение массива в специальной секции памяти, заданной в linker_script.ld
    // Выключаем инициализацию нулями, чтобы не затереть данные при перезагрузке
    __attribute__((section(".eeprom_log_section"), used))
    LogEntry m_buffer[MAX_ENTRIES];

    std::atomic<uint32_t> m_head;
    std::atomic<uint32_t> m_tail;
};

#endif // EEPROM_STORAGE_LOGGER_HPP
