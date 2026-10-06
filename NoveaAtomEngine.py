import math
import time
from typing import Dict, List, Optional
from dataclasses import dataclass

# --- 1. ТИПЫ ДАННЫХ И КОНТУРЫ ТЕЛЕМЕТРИИ ---

class VehicleClass:
    CLASS_A_WIRED = "Wired"     # Классические сеточные
    CLASS_B_AUTONOMOUS = "Auto" # Автономные с ТАХ и инерцоидом

@dataclass
class TelemetryFrame:
    vehicle_id: str
    v_class: str
    coordinates: tuple[float, float]  # (latitude, longitude)
    speed_kmh: float
    passenger_count: int               # Массо-габаритный контур (Δm)
    soc: float                         # Уровень заряда батареи % (0.0 - 100.0)
    inertia_energy_j: float            # Энергия в инерцоиде (Дж)
    contact_wires_connected: bool      # Статус токоприемников (штанг)
    h_climate_active: bool            # Климат-контроль / печка

# --- 2. МАТЕМАТИЧЕСКОЕ ЯДРО СИСТЕМЫ (Σ-FDL) ---

class NoveaAtomEngine:
    def __init__(self, wired_geofence: List[tuple[float, float]]):
        # Базовая геозона контактной сети Николаева
        self.wired_geofence = wired_geofence 
        # Виртуальный реестр модульных пит-стопов (хабов) на АЗС агломерации
        self.battery_hubs: Dict[str, int] = {
            "Balovnoe_Hub": 5,
            "Galitsynovka_Hub": 4,
            "Meshkovo_Hub": 6,
            "Voskresenskoe_Hub": 3
        }

    def check_geofence(self, coords: tuple[float, float]) -> bool:
        """Проверка нахождения в пределах контактной сети (упрощенный радиус-фильтр)"""
        for point in self.wired_geofence:
            # Расчет расстояния между точками (условно до 5 метров отклонения)
            dist = math.sqrt((coords[0] - point[0])**2 + (coords[1] - point[1])**2)
            if dist < 0.00005: # Около 5 метров в проекции координат
                return True
        return False

    def calculate_k_sn(self, frame: TelemetryFrame) -> float:
        """
        Расчет коэффициента совершенствования K_sn = NR_база / NR_факт
        Нормирование ресурса идет на один пассажиро-километр (ФЕ).
        """
        # Базовый абстрактно-необходимый норматив ресурсоемкости на 1 пассажиро-километр
        nr_base = 0.15 # кВт*ч / ФЕ (условная норма)
        
        # Расчет фактического энергопотребления (конкретно-необходимое выражение)
        base_mass = 12000 # кг (пустой троллейбус)
        passenger_mass = frame.passenger_count * 75 # Δm
        total_mass = base_mass + passenger_mass
        
        # Динамическая кинетическая составляющая расхода от массы и скорости
        kinetic_factor = 0.5 * total_mass * ((frame.speed_kmh / 3.6)**2) / 3600000 # в кВт*ч
        
        # Расход вспомогательных систем
        climate_load = 0.05 if frame.h_climate_active else 0.01
        
        nr_fact = (kinetic_factor + climate_load) / max(1, frame.passenger_count)
        
        # Защита от деления на ноль и расчет K_sn
        if nr_fact == 0:
            return 1.0
        return nr_base / nr_fact

    def resolve_contradictions(self, frame: TelemetryFrame) -> Dict[str, any]:
        """Логика разрешения системных противоречий Σ-FDL (Ветвление)"""
        k_sn = self.calculate_k_sn(frame)
        in_network = self.check_geofence(frame.coordinates)
        
        actions = {
            "vehicle_id": frame.vehicle_id,
            "k_sn": round(k_sn, 3),
            "status": "OK",
            "commands": []
        }

        # --- КЛАСС А: Сеточные троллейбусы ---
        if frame.v_class == VehicleClass.CLASS_A_WIRED:
            if not in_network and frame.contact_wires_connected:
                actions["status"] = "CRITICAL_ERROR"
                actions["commands"].append("EMERGENCY_BRAKE: Выход из среды обитания (риск обрыва штанг)")
            else:
                actions["commands"].append("STANDARD_WIRED_MODE: Потребление от сети")

        # --- КЛАСС B: Автономный ход ---
        elif frame.v_class == VehicleClass.CLASS_B_AUTONOMOUS:
            if not frame.contact_wires_connected:
                # Расчет динамической квазинормы запаса хода Z_km
                # Z_km = f(SOC, Δm, P_klima, E_kin)
                consumption_rate = 1.0 + (frame.passenger_count * 0.02) + (0.15 if frame.h_climate_active else 0.0)
                # Учет помощи инерцоида (снижает скорость падения заряда батареи)
                if frame.inertia_energy_j > 100000:
                    consumption_rate -= 0.25 # Инерцоид компенсирует пиковые нагрузки стартов
                
                z_km = (frame.soc / max(0.1, consumption_rate)) * 0.4
                actions["estimated_range_km"] = round(z_km, 1)

                # Управление дефицитом заряда
                if frame.soc < 30.0:
                    actions["status"] = "WARNING_LOW_BATTERY"
                    if frame.inertia_energy_j > 0:
                        actions["commands"].append("ACTIVATE_INERTIOID_DISCHARGE: Принудительное сглаживание пиков мощности")
                    actions["commands"].append("CORRECT_SPEED_PROFILE: Оптимизация скорости до ближайшей сети")
                else:
                    actions["commands"].append(f"AUTONOMOUS_WALK_MODE: Запас хода {round(z_km, 1)} км")
            else:
                # Возврат под сеть: динамическая зарядка в движении с лимитом тока подстанции
                actions["commands"].append("DYNAMIC_CHARGING_ACTIVE: Ограничение тока заряда на фидере")

        return actions

# --- 3. СИСТЕМНЫЙ СИНТЕЗ, БАЛАНСИРОВКА ГРАФОВ И ЛОГИСТИКА БАТАРЕЙ ---

class NoveaDispatcherSupervisor:
    def __init__(self, engine: NoveaAtomEngine):
        self.engine = engine
        self.vehicles_schedule_offset: Dict[str, float] = {} # Смещение графика в секундах

    def balance_network_grid(self, telemetry_snapshots: List[TelemetryFrame]):
        """Синтез данных и превентивное устранение волновых заторов"""
        for frame in telemetry_snapshots:
            actions = self.engine.resolve_contradictions(frame)
            
            # Компенсация массы на автономном участке
            if frame.v_class == VehicleClass.CLASS_B_AUTONOMOUS and not frame.contact_wires_connected:
                if frame.passenger_count > 80 and frame.soc < 40.0:
                    print(f"[СИНТЕЗ АТОМ] ТС {frame.vehicle_id} перегружено ({frame.passenger_count} чел.). Ресурс SOC истощается.")
                    print("--> КОМАНДА ДИСПЕТЧЕРУ: Выпустить дополнительный борт Класса B на маршрут.")

            # Устранение волновых заторов ("паровозиков")
            if frame.speed_kmh < 5.0 and frame.v_class == VehicleClass.CLASS_B_AUTONOMOUS:
                # Зафиксировано конкретно-необходимое отставание на автономном участке (пробка)
                delay_detected = 180.0 # 3 минуты задержки в секторе (например, Матвеевка или Корабельный)
                self.vehicles_schedule_offset[frame.vehicle_id] = delay_detected
                print(f"[БАЛАНСИРОВКА СЕТИ] ТС {frame.vehicle_id} застряло на автономном участке.")
                print("--> ДИСПЕТЧЕРСКИЙ МАНЕВР: Сдвиг графиков идущих следом машин Класса А для выравнивания тока.")

    def optimize_battery_turnover(self, hub_name: str, forecast_passengers: int):
        """ИИ-управление оборачиваемостью съемных аккумуляторов на пригородных пит-стопах"""
        required_modules = math.ceil(forecast_passengers / 25) # Коэффициент масштабирования ФЕ
        available = self.engine.battery_hubs.get(hub_name, 0)
        
        print(f"\n[ЛОГИСТИКА НОВЕЯ] Проверка пригородного хаба АЗС: {hub_name}")
        print(f"Прогноз пассажиропотока (студенты/дачники): {forecast_passengers} ФЕ. Требуется АКБ модулей: {required_modules}")
        
        if available < required_modules:
            deficit = required_modules - available
            print(f"--> ДЕФИЦИТ ОБНАРУЖЕН: {deficit} модулей. Запуск перераспределения логистического цикла.")
            self.engine.battery_hubs[hub_name] += deficit
        else:
            print("--> РЕСУРС ХАБА В НОРМЕ: Бесперебойность цикла обеспечена.")


# --- 4. ДЕМОНСТРАЦИЯ И СИМУЛЯЦИЯ РАБОТЫ ЦИКЛА (Николаевские маршруты) ---

if __name__ == "__main__":
    # Координатная сетка фидеров (контактной линии) по пр. Богоявленскому (Корабельный район)
    nikolaev_wire_zone = [(46.9012, 32.0612), (46.8950, 32.0640), (46.8820, 32.0710)]
    
    # Инициализация ядра системы «НОВЕЯ АТОМ»
    core_engine = NoveaAtomEngine(wired_geofence=nikolaev_wire_zone)
    supervisor = NoveaDispatcherSupervisor(engine=core_engine)

    print("="*80)
    print("ЗАПУСК ИИ-ДИСПЕТЧЕРА «НОВЕЯ АТОМ» (База: КП Николаевэлектротранс)")
    print("="*80)

    # Симуляция 1: Борт № 3001 (Класс B, Автономный ход, маршрут в Кульбакино, просадка батареи)
    # Штанги опущены, но работает инерцоид
    board_3001 = TelemetryFrame(
        vehicle_id="Борт-3001(Auto)",
        v_class=VehicleClass.CLASS_B_AUTONOMOUS,
        coordinates=(46.8710, 32.0950), # За пределами проводов сети
        speed_kmh=42.0,
        passenger_count=85,             # Высокий пассажиропоток (Δm)
        soc=28.5,                       # Заряд упал ниже критических 30%
        inertia_energy_j=150000.0,      # Есть накопленная кинетика в инерцоиде
        contact_wires_connected=False,  # Автономный ход
        h_climate_active=True
    )

    # Симуляция 2: Борт № 2012 (Класс А, Сеточный, пр. Богоявленский - соскочили штанги)
    board_2012 = TelemetryFrame(
        vehicle_id="Борт-2012(Wired)",
        v_class=VehicleClass.CLASS_A_WIRED,
        coordinates=(46.5000, 31.9000), # Машина улетела мимо геозоны проводов
        speed_kmh=12.0,
        passenger_count=30,
        soc=100.0,
        inertia_energy_j=0.0,
        contact_wires_connected=True,   # Попытка съема тока вне сети
        h_climate_active=False
    )

    # Обработка мгновенного пула телеметрии в реальном времени
    snapshots = [board_3001, board_2012]
    
    print("\n[ЭТАП 2 и 3: Оценка энтропии и разрешение противоречий]")
    for frame in snapshots:
        res = core_engine.resolve_contradictions(frame)
    print(f"\nТС: {res['vehicle_id']} | Оценка K_sn: {res['k_sn']} | Статус: {res['status']}")
    for cmd in res["commands"]:
    print(f"  └─> КОМАНДА БОРТУ: {cmd}")
    print("\n" + "="*80)
    print("[ЭТАП 4: Системный синтез и балансировка графов парка]")
    print("="*80)
    supervisor.balance_network_grid(snapshots)
    # Масштабирование: Анализ пригородного пит-стопа на трассе в Баловное
    # Утренний наплыв пассажиров/студентов в Николаев
    supervisor.optimize_battery_turnover(hub_name="Balovnoe_Hub", forecast_passengers=180)
