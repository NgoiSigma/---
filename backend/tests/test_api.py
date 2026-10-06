import pytest
import time
import httpx
import json

# Фиктивная конечная точка API диспетчера (замените на реальную при деплое)
API_URL = "http://localhost:8080/api/v1/telemetry"

# Фикстура с эталонным пакетом телеметрии
@pytest.fixture
def valid_telemetry_payload():
    return {
        "dev_id": 101,
        "spd_kmh": 45,
        "soc": 85,
        "mass_kg": 18500,
        "doors": 0,
        "k_sn": 1250
    }

@pytest.mark.asyncio
async def test_telemetry_ingestion_latency(valid_telemetry_payload):
    """
    Проверка времени отклика API.
    Для транспортного диспетчера задержка не должна превышать 50 мс.
    """
    async with httpx.AsyncClient() as client:
        start_time = time.perf_counter()
        response = await client.post(API_URL, json=valid_telemetry_payload)
        end_time = time.perf_counter()

    latency_ms = (end_time - start_time) * 1000
    
    assert response.status_code == 200, f"API вернул ошибку: {response.status_code}"
    assert latency_ms < 50.0, f"Задержка API слишком высока: {latency_ms:.2f} мс"

@pytest.mark.asyncio
async def test_invalid_json_rejection():
    """
    Проверка защиты шлюза от некорректных данных (например, обрыв связи).
    """
    malformed_json = '{"dev_id": 101, "spd_kmh": ' # Неожиданный конец строки
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            API_URL, 
            content=malformed_json,
            headers={"Content-Type": "application/json"}
        )
    
    # Ожидаем 400 Bad Request от валидатора
    assert response.status_code == 400

@pytest.mark.asyncio
async def test_ksn_bounds(valid_telemetry_payload):
    """
    Проверка граничных значений нормировочного коэффициента K_sn.
    """
    payload = valid_telemetry_payload.copy()
    payload["k_sn"] = 70000  # Выход за пределы uint16_t (макс 65535)

    async with httpx.AsyncClient() as client:
        response = await client.post(API_URL, json=payload)
    
    # API должен отклонить пакет с нереалистичным K_sn
    assert response.status_code == 422
