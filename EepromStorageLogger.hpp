#ifndef EEPROM_STORAGE_LOGGER_HPP
#define EEPROM_STORAGE_LOGGER_HPP

#include <cstdint>
#include <cstddef>

constexpr size_t EEPROM_LOG_CAPACITY = 128; // Максимальное количество удерживаемых логов в кольце
constexpr uint32_t EEPROM_START_ADDRESS = 0x08080000; // Базовый сектор памяти

struct ErrorLogEntry {
    uint32_t timestamp_sec;
    uint8_t  error_code;
    float    critical_value;
    uint16_t vehicle_id;
};

class EepromStorageLogger {
private:
    ErrorLogEntry m_ring_buffer[EEPROM_LOG_CAPACITY];
    size_t m_head = 0;
    size_t m_tail = 0;
    size_t m_size = 0;

    // Внутренняя низкоуровневая запись байтов в эмулируемую ячейку памяти
    void physical_flash_write(uint32_t address, const void* data, size_t bytes) {
        // На аппаратном уровне здесь располагаются вызовы драйвера:
        // HAL_FLASH_Program или eeprom_write_block
        (void)address; (void)data; (void)bytes;
    }

public:
    EepromStorageLogger() = default;

    bool log_error(uint32_t timestamp, uint8_t code, float value, uint16_t v_id) {
        ErrorLogEntry entry{ timestamp, code, value, v_id };

        // Запись в текущую позицию головы кольца
        m_ring_buffer[m_head] = entry;
        
        // Расчет физического смещения адреса во Flash
        uint32_t flash_address = EEPROM_START_ADDRESS + (static_cast<uint32_t>(m_head) * sizeof(ErrorLogEntry));
        physical_flash_write(flash_address, &entry, sizeof(ErrorLogEntry));

        m_head = (m_head + 1) % EEPROM_LOG_CAPACITY;

        if (m_size < EEPROM_LOG_CAPACITY) {
            m_size++;
        } else {
            // Если буфер переполнен, хвост сдвигается вперед (перезапись старых логов)
            m_tail = (m_tail + 1) % EEPROM_LOG_CAPACITY;
        }
        return true;
    }

    bool pop_oldest_log(ErrorLogEntry& out_entry) {
        if (m_size == 0) {
            return false; // Логов нет, память пуста
        }

        out_entry = m_ring_buffer[m_tail];
        m_tail = (m_tail + 1) % EEPROM_LOG_CAPACITY;
        m_size--;
        return true;
    }

    size_t get_active_logs_count() const { return m_size; }
    void clear_storage() { m_head = 0; m_tail = 0; m_size = 0; }
};

#endif // EEPROM_STORAGE_LOGGER_HPP
