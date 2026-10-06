-- ==============================================================================
-- СХЕМА ДАННЫХ «НОВЕЯ АТОМ»: РАСШИРЕННАЯ ДИСПЕТЧЕРИЗАЦИЯ И ГЕОАНАЛИТИКА
-- Оптимизировано под секундный лог с использованием TimescaleDB и PostGIS
-- ==============================================================================

-- Шаг 1: Активация необходимых расширений (выполняется под superuser)
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
CREATE EXTENSION IF NOT EXISTS postgis CASCADE;

-- Шаг 2: Удаление существующих структур при их наличии для обеспечения чистой сборки
DROP TABLE IF EXISTS vehicle_telemetry_hyper CASCADE;

-- Шаг 3: Создание базовой структуры таблицы секундной телеметрии парка
CREATE TABLE vehicle_telemetry_hyper (
    time                TIMESTAMPTZ NOT NULL,
    vehicle_id          INT NOT NULL,
    speed_kmh           REAL NOT NULL,
    soc                 REAL NOT NULL,
    mass_kg             INT NOT NULL,
    k_sn                REAL NOT NULL,
    inertia_energy_j    REAL NOT NULL,
    contact_wires       BOOLEAN NOT NULL,
    -- Пространственная точка PostGIS (SRID 4326 - WGS 84 GPS координаты)
    geom_point          GEOMETRY(Point, 4326) NOT NULL
);

-- Шаг 4: Преобразование таблицы в гипертаблицу (Hypertable)
-- chunk_time_interval задает автоматическую нарезку на физические секции по 7 суток
SELECT create_hypertable(
    'vehicle_telemetry_hyper', 
    'time', 
    chunk_time_interval => INTERVAL '7 days'
);

-- Шаг 5: Создание комбинированных индексов для ускорения аналитических выборок диспетчера
-- Эффективно для поиска заторов конкретного троллейбуса во временном окне
CREATE INDEX idx_vehicle_time ON vehicle_telemetry_hyper (vehicle_id, time DESC);

-- Пространственный R-Tree индекс PostGIS для ускорения секундных проверок попадания в геозону
CREATE INDEX idx_vehicle_spatial ON vehicle_telemetry_hyper USING GIST (geom_point);

-- Шаг 6: Настройка политики сжатия данных (Compression Policy)
-- Позволяет экономить до 90% дискового пространства на бортовом сервере
ALTER TABLE vehicle_telemetry_hyper SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'vehicle_id',
    timescaledb.compress_orderby = 'time DESC'
);

-- Активация автоматического сжатия данных старше 14 дней
SELECT add_compression_policy('vehicle_telemetry_hyper', INTERVAL '14 days');

-- ==============================================================================
-- ПРИМЕР ПОВЕРОЧНОГО ЗАПРОСА ГЕОЗОНЫ (Оптимизированный пространственный поиск)
-- Выборка всех троллейбусов, находившихся вне геозоны проводов за последние 5 минут
-- ==============================================================================
/*
SELECT time, vehicle_id, speed_kmh, soc 
FROM vehicle_telemetry_hyper
WHERE time > NOW() - INTERVAL '5 minutes'
  AND NOT ST_Contains(
      -- Геометрия полигона контактной сети проспекта Богоявленского (пример полигона)
      ST_GeomFromText('POLYGON((32.061 46.901, 32.064 46.895, 32.071 46.882, 32.061 46.901))', 4326),
      geom_point
  );
*/
