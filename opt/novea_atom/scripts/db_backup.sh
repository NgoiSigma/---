#!/bin/bash

# ==============================================================================
# НАИМЕНОВАНИЕ: db_backup.sh
# НАЗНАЧЕНИЕ: Автоматический бэкап TimescaleDB «НОВЕЯ АТОМ» в облако горсовета
# ==============================================================================

set -euo pipefail

# --- КОНФИГУРАЦИЯ СРЕДЫ ---
DB_NAME="novea_dispatch_db"
DB_USER="postgres"
BACKUP_LOCAL_DIR="/opt/novea_atom/storage/backups"
DATE_SUFFIX=$(date '+%Y%m%d_%H%M%S')
BACKUP_NAME="timescaledb_${DB_NAME}_${DATE_SUFFIX}"
LOCAL_TAR_PATH="${BACKUP_LOCAL_DIR}/${BACKUP_NAME}.tar.gz"

# --- КОНФИГУРАЦИЯ УДАЛЕННОГО ОБЛАКА СЕРВЕРА ГОРСОВЕТА ---
REMOTE_USER="mkrada_backup"
REMOTE_HOST="cloud.mkrada.gov.ua"
REMOTE_DIR="/mnt/secure_storage/electrotrans/db"
SSH_KEY="/home/postgres/.ssh/id_rsa_cloud"

# Логирование
LOG_FILE="/var/log/novea_atom/backup.log"
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "${BACKUP_LOCAL_DIR}"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- ШАГ 1: Блокировка и создание дампа (Снятие слепка без остановки СУБД) ---
log_msg "Старт резервного копирования базы данных ${DB_NAME}..."

# Использование многопоточного формата каталога (-Fd) для ускорения
# Ключ --blobs обязателен для сохранения пространственных индексов PostGIS
pg_dump -U ${DB_USER} -d ${DB_NAME} -Fd -j 4 -b -f "${BACKUP_LOCAL_DIR}/${BACKUP_NAME}"

# Архивация каталога дампа в единый сжатый файл
tar -czf "${LOCAL_TAR_PATH}" -C "${BACKUP_LOCAL_DIR}" "${BACKUP_NAME}"
rm -rf "${BACKUP_LOCAL_DIR}/${BACKUP_NAME}" # Удаление несжатой временной папки

# --- ШАГ 2: Передача архива на удаленное облачное хранилище по SFTP ---
log_msg "Выгрузка архива в облачное хранилище горсовета (${REMOTE_HOST})..."

if [ -f "${LOCAL_TAR_PATH}" ]; then
    # Передача по защищенному каналу с использованием SSH-ключа (без ввода пароля)
    scp -i "${SSH_KEY}" -P 2222 "${LOCAL_TAR_PATH}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"
    log_msg "Файл успешно передан в облако."
else
    log_msg "КРИТИЧЕСКАЯ ОШИБКА: Файл бэкапа не найден!"
    exit 1
fi

# --- ШАГ 3: Ротация старых копий на локальном сервере (Храним последние 7 дней) ---
log_msg "Очистка устаревших локальных копий..."
find "${BACKUP_LOCAL_DIR}" -type f -name "timescaledb_*.tar.gz" -mtime +7 -delete

log_msg "Резервное копирование успешно завершено."
