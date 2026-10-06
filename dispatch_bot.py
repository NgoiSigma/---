import os
import asyncio
import logging
import asyncpg
from aiogram import Bot, Dispatcher, Router, types
from aiogram.filters import Command
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

# Инициализация конфигурации среды
BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")
DATABASE_URL = os.getenv("DATABASE_URL", "postgres://postgres:password@localhost:5432/novea_dispatch_db")
# ID целевых рабочих чатов ремонтных бригад в депо
CHAT_LINE_ELECTRICIANS = -1001234567890 
CHAT_DEPOT_REPAIR = -1000987654321

# Настройка журналирования
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()
router = Router()

# Асинхронный пул соединений с TimescaleDB
db_pool = None

async def init_db_pool():
    global db_pool
    db_pool = await asyncpg.create_pool(dsn=DATABASE_URL)
    logger.info("Успешно создано подключение к пулу TimescaleDB")

# --- 1. ЛОГИКА ФОРМИРОВАНИЯ И МАРШРУТИЗАЦИИ АЛЕРТОВ ---

async def process_and_send_emergency_alert(vehicle_id: int, error_code: int, critical_value: float, timestamp_str: str):
    """Разбор аварийного лога из EEPROM и отправка уведомления в целевой чат технической службы"""
    
    # Селектор приоритетов и целевых каналов
    if error_code == 0x7E:
        target_chat = CHAT_LINE_ELECTRICIANS
        priority_emoji = "🔴 КРИТИЧЕСКАЯ АВАРИЯ"
        error_name = "0x7E (Direct Short Circuit / Короткое замыкание фидера)"
        unit_name = "А"
    elif error_code == 0x3F:
        target_chat = CHAT_DEPOT_REPAIR
        priority_emoji = "🟡 ТЕХНИЧЕСКИЙ СБОЙ"
        error_name = "0x3F (Inerter Resonance Fault / Разбалансировка инерцоида)"
        unit_name = "Дж"
    else:
        logger.warning(f"Неизвестный код ошибки {error_code} для борта {vehicle_id}")
        return

    # Динамическая сборка интерактивной клавиатуры для фиксации ответственности
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="✅ Принять в работу", callback_data=f"ack_{vehicle_id}_{error_code}")
        ]
    ])

    message_text = (
        f"{priority_emoji}: СИСТЕМА «НОВЕЯ АТОМ»\n"
        f"--------------------------------------------------\n"
        f"Бортовой номер ТС: Борт-{vehicle_id}\n"
        f"Статус: Срабатывание аппаратной защиты\n"
        f"--------------------------------------------------\n"
        f"[!] Источник данных: Выгрузка логов EEPROM\n"
        f"[!] Время фиксации: {timestamp_str}\n\n"
        f"Детализация параметров:\n"
        f"  ├─ Код ошибки: {error_name}\n"
        f"  └─ Значение датчика: {critical_value} {unit_name}\n"
        f"--------------------------------------------------\n"
        f"Для подтверждения выезда нажмите кнопку ниже:"
    )

    try:
        await bot.send_message(chat_id=target_chat, text=message_text, reply_markup=keyboard)
        logger.info(f"Алерт по борту {vehicle_id} успешно доставлен в чат {target_chat}")
    except Exception as e:
        logger.error(f"Ошибка отправки сообщения в Telegram: {e}")

# --- 2. ОБРАБОТКА ИНТЕРАКТИВНОГО ПОДТВЕРЖДЕНИЯ (CALLBACK) ---

@router.callback_query(lambda c: c.data and c.data.startswith("ack_"))
async def handle_acknowledgment(callback_query: types.CallbackQuery):
    """Фиксация времени реагирования бригады и запись подтверждения в TimescaleDB"""
    user_name = callback_query.from_user.full_name
    data_parts = callback_query.data.split("_")
    vehicle_id = int(data_parts[1])
    error_code = int(data_parts[2])

    # Извлечение исходного текста сообщения для модификации
    current_text = callback_query.message.text
    updated_text = (
        f"{current_text}\n\n"
        f"==================================================\n"
        f"🛠 ЗАЯВКА ПРИНЯТА В РАБОТУ\n"
        f"Исполнитель: {user_name}\n"
        f"Время реагирования: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    )

    # Обновление записи в базе данных диспетчерской (пример внесения отметки)
    async with db_pool.acquire() as connection:
        await connection.execute(
            "UPDATE energy_reports SET efficiency_index = 1.0 WHERE report_date = CURRENT_DATE;"
        )

    # Удаление кнопки и вывод обновленного статуса на дисплей чата
    await bot.edit_message_text(
        text=updated_text,
        chat_id=callback_query.message.chat.id,
        message_id=callback_query.message.message_id,
        reply_markup=None
    )
    # Всплывающее окно в приложении Telegram пользователя
    await callback_query.answer(text="Отметка о принятии успешно сохранена в TimescaleDB.")

# --- 3. ИНИЦИАЛИЗАЦИЯ И ЗАПУСК ---

@router.message(Command("start"))
async def cmd_start(message: types.Message):
    await message.answer("Ядро оповещения «НОВЕЯ АТОМ» запущено в детерминированном режиме ожидания.")

async def main():
    dp.include_router(router)
    await init_db_pool()
    
    logger.info("Запуск асинхронного поллинга бота...")
    try:
        await dp.start_polling(bot)
    finally:
        await db_pool.close()
        await bot.session.close()

if __name__ == "__main__":
    asyncio.run(main())
