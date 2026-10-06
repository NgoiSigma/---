-- Активация необходимых расширений
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
CREATE EXTENSION IF NOT EXISTS postgis CASCADE;

-- Таблица сырой телеметрии с бортовых контроллеров
CREATE TABLE IF NOT EXISTS trolleybus_telemetry (
    time        TIMESTAMPTZ NOT NULL,
    device_id   INTEGER NOT NULL,
    speed_kmh   SMALLINT NOT NULL,
    soc_percent SMALLINT NOT NULL,
    mass_kg     INTEGER NOT NULL,
    k_sn        INTEGER NOT NULL,
    doors_open  BOOLEAN NOT NULL,
    location    GEOMETRY(Point, 4326) NOT NULL -- Геопозиция в формате WGS 84
);

-- Преобразование стандартной таблицы в гипертаблицу TimescaleDB
-- Нарезка чанков (секционирование) по 7 дней для оптимальной работы с RAM
SELECT create_hypertable('trolleybus_telemetry', 'time', chunk_time_interval => INTERVAL '7 days');

-- Создание R-Tree индекса PostGIS для быстрого поиска машин в заданном радиусе/полигоне
CREATE INDEX idx_telemetry_location ON trolleybus_telemetry USING GIST (location);

-- Индекс для фильтрации по конкретной машине (полезно для построения исторического трека)
CREATE INDEX idx_telemetry_device_time ON trolleybus_telemetry (device_id, time DESC);

-- Настройка политики компрессии старых данных (старше 14 дней)
ALTER TABLE trolleybus_telemetry SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('trolleybus_telemetry', INTERVAL '14 days');

-- Таблица для регистрации критических событий (лог ошибок)
CREATE TABLE IF NOT EXISTS system_alerts (
    id SERIAL PRIMARY KEY,
    time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    device_id INTEGER NOT NULL,
    error_code SMALLINT NOT NULL,
    recorded_value INTEGER NOT NULL,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_by VARCHAR(100)
);
