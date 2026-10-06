cmake_minimum_required(VERSION 3.10)
project(NoveaAtom_Firmware CXX C)

# Стандарт C++17 для современных фичей без кучи (std::optional, constexpr)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Флаги компиляции для Bare-Metal / RT-Preempt
# Исключаем динамическую память, исключения и RTTI для отказоустойчивости
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -Wall -Wextra -Wpedantic -fno-exceptions -fno-rtti -fno-threadsafe-statics")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -Wall -Wextra")

# Глобальный дефайн для блокировки случайного вызова malloc/new
add_compile_definitions(NO_DYNAMIC_ALLOCATION)

include_directories(include)

# Собираем все исходники
file(GLOB SOURCES "src/*.cpp")

add_executable(${PROJECT_NAME}.elf ${SOURCES})

# Подключаем кастомный linker script для секции логов
set_target_properties(${PROJECT_NAME}.elf PROPERTIES LINK_FLAGS "-T ${CMAKE_CURRENT_SOURCE_DIR}/linker_script.ld -Wl,-Map=${PROJECT_NAME}.map,--gc-sections")

# Пост-билд генерация бинарника для прошивки и вывод размера
add_custom_command(TARGET ${PROJECT_NAME}.elf POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary ${PROJECT_NAME}.elf ${PROJECT_NAME}.bin
    COMMAND ${CMAKE_SIZE} ${PROJECT_NAME}.elf
)
