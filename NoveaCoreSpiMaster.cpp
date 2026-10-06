#include <iostream>
#include <cstdint>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>

class NoveaCoreSpiMaster {
private:
    int m_spi_fd = -1;
    const char* m_device = "/dev/spidev0.0";
    uint8_t m_mode = SPI_MODE_0;
    uint8_t m_bits = 8; // Передача побайтово
    uint32_t m_speed_hz = 5000000; // 5 МГц тактовая частота SPI

    // Статическое вычисление контрольной суммы CRC-8 (Полином 0x07, эквивалент ATM-8)
    uint8_t calculate_crc8(const uint8_t* data, size_t length) const {
        uint8_t crc = 0x00;
        for (size_t i = 0; i < length; ++i) {
            crc ^= data[i];
            for (uint8_t bit = 0; bit < 8; ++bit) {
                if (crc & 0x80) {
                    crc = static_cast<uint8_t>((crc << 1) ^ 0x07);
                } else {
                    crc = static_cast<uint8_t>(crc << 1);
                }
            }
        }
        return crc;
    }

public:
    NoveaCoreSpiMaster() = default;
    
    bool init_spi() {
        m_spi_fd = open(m_device, O_RDWR);
        if (m_spi_fd < 0) return false;

        if (ioctl(m_spi_fd, SPI_IOC_WR_MODE, &m_mode) < 0) return false;
        if (ioctl(m_spi_fd, SPI_IOC_WR_BITS_PER_WORD, &m_bits) < 0) return false;
        if (ioctl(m_spi_fd, SPI_IOC_WR_MAX_SPEED_HZ, &m_speed_hz) < 0) return false;

        return true;
    }

    // Сборка 24-битного кадра для ПЛИС
    bool send_control_packet(bool charge_enable, uint16_t duty_cycle) {
        if (m_spi_fd < 0) return false;

        uint8_t tx_buffer[3] = {0};

        // Заполнение первых 16 информационных бит [23:8] кадра
        // Бит 19: charge_enable. Младшие 11 бит [18:8]: duty_cycle
        tx_buffer[0] = static_cast<uint8_t>((charge_enable ? 0x08 : 0x00) | ((duty_cycle >> 8) & 0x07));
        tx_buffer[1] = static_cast<uint8_t>(duty_cycle & 0xFF);

        // Байт 0 [7:0]: Расчет контрольной суммы над первыми 2 байтами
        tx_buffer[2] = calculate_crc8(tx_buffer, 2);

        struct spi_ioc_transfer tr{};
        tr.tx_buf = reinterpret_cast<unsigned long>(tx_buffer);
        tr.rx_buf = 0; // Нам не важен прием в этой задаче
        tr.len = 3;    // Фиксированный 24-битный размер
        tr.speed_hz = m_speed_hz;
        tr.bits_per_word = m_bits;
        tr.delay_usecs = 0;

        if (ioctl(m_spi_fd, SPI_IOC_MESSAGE(1), &tr) < 1) {
            return false;
        }
        return true;
    }

    ~NoveaCoreSpiMaster() {
        if (m_spi_fd >= 0) close(m_spi_fd);
    }
};

int main() {
    NoveaCoreSpiMaster spi_controller;
    if (!spi_controller.init_spi()) {
        std::cerr << "Сбой инициализации шины SPI" << std::endl;
        return -1;
    }

    // Тестовая отправка: Активация заряда, уставка duty_cycle = 500 тактов ПЛИС
    if (spi_controller.send_control_packet(true, 500)) {
        std::printf("[Cortex-A7 SPI] Пакет 24-бит с расчитанным CRC-8 успешно отправлен.\n");
    }
    return 0;
}
