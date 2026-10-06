import pytest
import requests
import datetime
import random

# Конфигурация интеграционного стенда диспетчерской Николаева
BASE_URL = "http://mkrada.gov.ua"
TEST_VEHICLE_ID = 9999  # Выделенный ID для отладочного борта

@pytest.fixture
def telemetry_payload():
    """Генератор эталонного фрейма секундной телеметрии (Σ-FDL контур)"""
    return {
        "v_id": TEST_VEHICLE_ID,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "metrics": {
            "speed": round(random.uniform(20.0, 50.0), 2),
            "soc": 45.5,
            "mass": 15400,
            "inertia_j": 120000.0
        },
        "fdl_status": {
            "k_sn": 0.985,
            "range_left_km": 22.1,
            "wires_connected": False,
            "inerter_fault": False
        }
    }

def test_01_publish_telemetry_endpoint(telemetry_payload):
    """Проверка записи секундного кадра через шлюз API в гипертаблицу TimescaleDB"""
    url = f"{BASE_URL}/vehicles/{TEST_VEHICLE_ID}/telemetry"
    response = requests.post(url, json=telemetry_payload, timeout=2.0)
    
    assert response.status_code == 202, f"Неверный статус ответа: {response.status_code}"
    data = response.json()
    assert data["status"] == "accepted"
    assert "transaction_id" in data

def test_02_verify_timescaledb_query_performance():
    """Проверка опрашивающего REST API на скорость извлечения чанков из TimescaleDB.
    Время выполнения пространственно-временного запроса PostGIS не должно превышать 50мс.
    """
    url = f"{BASE_URL}/sections/12/status"
    
    # Замер интервала времени ответа базы данных (Latency)
    start_time = datetime.datetime.now()
    response = requests.get(url, timeout=2.0)
    end_time = datetime.datetime.now()
    
    duration_ms = (end_time - start_time).total_seconds() * 1000.0
    
    assert response.status_code == 200
    data = response.json()
    
    # Валидация структуры ответа аналитического ядра
    assert "grid_entropy" in data
    assert "active_load_fe" in data
    
    # Бенчмарк: проверка эффективности работы индексов Hypertable и R-Tree PostGIS
    assert duration_ms < 50.0, f"Критическая задержка TimescaleDB: {duration_ms:.2f} мс (Превышен лимит 50мс)"
    print(f"\n[BENCHMARK] Время ответа TimescaleDB + PostGIS: {duration_ms:.2f} мс")
