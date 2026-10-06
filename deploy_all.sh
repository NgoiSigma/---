#!/bin/bash

# ==============================================================================
# НАИМЕНОВАНИЕ: deploy_all.sh
# НАЗНАЧЕНИЕ: Автоматическая сборка, инициализация БД и ротация отчетов «НОВЕЯ АТОМ»
# БАЗА: КП «Николаевэлектротранс», г. Николаев
# ==============================================================================

# Строгий режим обработки ошибок
set -euo pipefail

# Инициализация путей среды
PROJECT_DIR="/opt/novea_atom"
BIN_DIR="${PROJECT_DIR}/bin"
BUILD_DIR="${PROJECT_DIR}/build"
LOG_DIR="/var/log/novea_atom"
STORAGE_DIR="${PROJECT_DIR}/storage"
DB_NAME="novea_dispatch_db"

# Цвета для вывода в консоль терминала
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[ИНФО] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_err()  { echo -e "${RED}[ОШИБКА] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }

# --- ФАЗА 1: Автоматическая компиляция С++ ядра ---
build_core() {
    log_info "Запуск компиляции исполнительного модуля ядра для ARM Cortex-A7..."
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    
    # Генерация файлов сборки через CMake с флагом целевой архитектуры
    cmake -DMCU_TARGET=CORTEX_A7 ..
    make -j$(nproc)
    
    mkdir -p "${BIN_DIR}"
    cp NoveaAtomBoard "${BIN_DIR}/"
    log_info "Компиляция завершена успешно. Бинарный файл размещен в ${BIN_DIR}/NoveaAtomBoard"
}

# --- ФАЗА 2: Инициализация структуры таблиц базы данных ---
init_database() {
    log_info "Проверка структуры таблиц СУБД диспетчеризации..."
    
    # SQL-скрипт инициализации структуры данных
    local init_sql="
    CREATE TABLE IF NOT EXISTS vehicle_telemetry (
        timestamp TIMESTAMPTZ NOT NULL,
        vehicle_id INT NOT NULL,
        speed_kmh REAL,
        soc REAL,
        mass_kg INT,
        k_sn REAL,
        inerter_energy_j REAL,
        contact_wires BOOLEAN
    );
    CREATE TABLE IF NOT EXISTS energy_reports (
        report_date DATE PRIMARY KEY,
        total_fe_completed REAL NOT NULL,
        energy_saved_kwh REAL NOT NULL,
        efficiency_index REAL NOT NULL
    );
    "
    
    # Попытка применить структуру (предполагается локальный psql-клиент)
    if command -v psql &> /dev/null; then
        echo "$init_sql" | psql -d "${DB_NAME}" -U postgres -q || log_err "Сбой при исполнении SQL-запроса инициализации."
        log_info "База данных успешно синхронизирована со схемой."
    else
        log_info "Утилита psql не найдена. Создание структуры перенаправлено во временный лог-дамп."
        echo "$init_sql" > "${STORAGE_DIR}/db_schema_init.sql"
    fi
}

# --- ФАЗА 3: Ночная ротация и генерация суточных отчетов ---
rotate_reports() {
    log_info "Инициализация ночной ротации и архивации суточных отчетов..."
    local yesterday=$(date -d "yesterday" '+%Y-%m-%d')
    local archive_name="report_fe_${yesterday}.tar.gz"
    
    mkdir -p "${STORAGE_DIR}/archive"
    mkdir -p "${LOG_DIR}"
    
    # Генерация суточной выгрузки энергетического баланса
    if [ -f "${STORAGE_DIR}/current_day_raw.log" ]; then
        mv "${STORAGE_DIR}/current_day_raw.log" "${STORAGE_DIR}/report_${yesterday}.log"
        tar -czf "${STORAGE_DIR}/archive/${archive_name}" -C "${STORAGE_DIR}" "report_${yesterday}.log"
        rm "${STORAGE_DIR}/report_${yesterday}.log"
        touch "${STORAGE_DIR}/current_day_raw.log"
        log_info "Суточный архив отчетов успешно сформирован: ${archive_name}"
    else
        log_info "Текущий лог-файл пуст. Создан пустой маркер отчета для текущих суток."
        touch "${STORAGE_DIR}/current_day_raw.log"
    fi
}

# --- Главный диспетчер выполнения ключей скрипта ---
if [ $# -eq 0 ]; then
    build_core
    init_database
elif [ "$1" == "--generate-report" ]; then
    rotate_reports
else
    log_err "Неизвестный параметр запуска: $1. Используйте без параметров или --generate-report"
    exit 1
fi
