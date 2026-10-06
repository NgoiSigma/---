## 🌐 Интеграционный API (Муниципальный контур)

Для обмена данными с внешними мониторинговыми порталами и городскими сервисами информирования комплекс «НОВЕЯ АТОМ» поддерживает два интерфейса: событийный (MQTT) и опросный (JSON REST API).

### 1. Протокол MQTT (Публикация телеметрии в реальном времени)

Каждый бортовой терминал осуществляет ежесекундную публикацию телеметрического кадра в брокер горсовета.

* **Топик:** `nikolaev/electrotrans/vehicles/{vehicle_id}/telemetry`
* **Формат сообщения (Payload JSON):**

```json
{
  "v_id": 3001,
  "timestamp": "2026-10-06T07:19:00Z",
  "metrics": {
    "speed": 42.00,
    "soc": 28.5,
    "mass": 18375,
    "inertia_j": 150000.0
  },
  "fdl_status": {
    "k_sn": 0.945,
    "range_left_km": 18.4,
    "wires_connected": false,
    "inerter_fault": false
  }
}
```

### 2. JSON REST API (Управление и внешние запросы)

Доступ к API осуществляется через шлюз центрального сервера диспетчеризации.

#### А. Запрос текущего энергетического статуса секции сети
* **HTTP Метод:** `GET`
* **Эндпоинт:** `/api/v1/sections/{section_id}/status`
* **Успешный ответ (200 OK):**

```json
{
  "section_id": 12,
  "location": "Prospekt_Bogoyavlenskiy",
  "active_load_fe": 14,
  "grid_entropy": "low",
  "recommended_shift_sec": 0
}
```

#### Б. Принудительное изменение уставки или сброс блокировки КЗ (Диспетчерский маневр)
Запрос посылается удаленно из центра управления для ручной корректировки параметров бортового ядра ШИМ (дублируется через SPI в ПЛИС).

* **HTTP Метод:** `POST`
* **Эндпоинт:** `/api/v1/vehicles/{vehicle_id}/control`
* **Тело запроса (JSON):**

```json
{
  "command_id": 402,
  "auth_token": "sig_fdl_secure_token_hash",
  "actions": {
    "sys_enable": true,
    "fault_clear": false,
    "interleave_en": true,
    "target_duty_cycle": 800
  }
}
```
* **Ответ сервера (202 Accepted):**

```json
{
  "status": "accepted",
  "transaction_id": "tx_3001_17989600",
  "execution_time_ms": 12
}
```

### 3. Обработка ошибок передачи данных
При передаче невалидных структурированных данных или нарушении контрольных сумм кадра, API возвращает стандартизированный код ошибки:

```json
{
  "error": {
    "code": 422,
    "message": "Unprocessable Entity",
    "details": "CRC-8 Verification Failed on Hardware Layer"
  }
}
```
