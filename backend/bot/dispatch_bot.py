import asyncio
import logging
from aiogram import Bot, Dispatcher, F
from aiogram.types import Message, InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery
from aiogram.filters import Command
from aiogram.enums import ParseMode

# Конфигурация
API_TOKEN = 'YOUR_TELEGRAM_BOT_TOKEN'
DISPATCH_CHANNEL_ID = -1001234567890 # ID группы ремонтной бригады

bot = Bot(token=API_TOKEN, parse_mode=ParseMode.HTML)
dp = Dispatcher()

# Коды критических ошибок
ALERT_CODES = {
    0x7E: "АППАРАТНАЯ ОТСЕЧКА (feeder_fault_n)",
    0x3F: "КРИТИЧЕСКАЯ ПОТЕРЯ ЭНЕРГИИ ВАКУУМНОЙ КАМЕРЫ"
}

# Генерация инлайн-клавиатуры для подтверждения
def get_ack_keyboard(alert_id: str) -> InlineKeyboardMarkup:
    buttons = [[InlineKeyboardButton(text="🛠 Принять в работу", callback_data=f"ack_{alert_id}")]]
    return InlineKeyboardMarkup(inline_keyboard=buttons)

# Функция для вызова из внешнего API/MQTT подписчика
async def broadcast_alert(device_id: int, error_code: int, value: int, lat: float, lon: float):
    error_desc = ALERT_CODES.get(error_code, "НЕИЗВЕСТНЫЙ СБОЙ")
    alert_id = f"{device_id}_{error_code}_{value}" # Простой генератор ID
    
    text = (
        f"🚨 <b>АВАРИЯ ТРОЛЛЕЙБУСА #{device_id}</b>\n\n"
        f"<b>Код:</b> {hex(error_code)} - {error_desc}\n"
        f"<b>Параметр:</b> {value}\n"
        f"<b>Локация:</b> <code>{lat}, {lon}</code>\n\n"
        f"<i>Требуется немедленная реакция ремонтной бригады!</i>"
    )
    
    await bot.send_message(
        chat_id=DISPATCH_CHANNEL_ID,
        text=text,
        reply_markup=get_ack_keyboard(alert_id)
    )

# Обработчик нажатия кнопки "Принять в работу"
@dp.callback_query(F.data.startswith("ack_"))
async def handle_acknowledgement(callback: CallbackQuery):
    alert_id = callback.data.split("_")[1:]
    user_name = callback.from_user.full_name
    
    # Редактируем сообщение, убирая кнопку и добавляя статус
    original_text = callback.message.html_text
    new_text = f"{original_text}\n\n✅ <b>Принято в работу:</b> {user_name}"
    
    await callback.message.edit_text(text=new_text, reply_markup=None)
    await callback.answer("Статус обновлен!")

@dp.message(Command("status"))
async def cmd_status(message: Message):
    await message.answer("Бот-диспетчер НОВЕЯ АТОМ активен и ожидает алертов.")

async def main():
    logging.basicConfig(level=logging.INFO)
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
