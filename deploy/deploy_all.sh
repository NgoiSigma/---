#!/bin/bash
set -e # Остановка при любой ошибке

echo "[*] Начинаем развертывание НОВЕЯ АТОМ..."

# 1. Сборка C++ ядра (с флагами для RT-Preempt)
echo "[*] Компиляция C++ демона..."
cd ../firmware_mcu
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
cp NoveaAtom_Firmware.elf /opt/novea_atom/bin/novea_daemon
cd ../../deploy

# 2. Инициализация TimescaleDB
echo "[*] Накатываем схему базы данных..."
sudo -u postgres psql -d novea_db -f ../backend/database/schema.sql

# 3. Установка Systemd служб
echo "[*] Установка systemd-сервисов..."
sudo cp systemd/novea-atom.service /etc/systemd/system/
sudo cp systemd/novea-backup.service /etc/systemd/system/
sudo cp systemd/novea-backup.timer /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable novea-atom.service
sudo systemctl enable novea-backup.timer

# 4. Настройка Nginx для Telegram-бота
echo "[*] Конфигурация Nginx..."
sudo cp nginx/novea_webhook.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/novea_webhook.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "[+] Развертывание успешно завершено!"
