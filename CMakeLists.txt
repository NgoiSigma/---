cmake_minimum_required(VERSION 3.15)
project(NoveaAtomBoard VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Определение целевой архитектуры через передачу флага -DMCU_TARGET=CORTEX_M4 или CORTEX_A7
set(MCU_TARGET "CORTEX_A7" CACHE STRING "Целевая архитектура бортового терминала")

if(MCU_TARGET STREQUAL "CORTEX_M4")
    message(STATUS "Конфигурация сборки под Bare-Metal/FreeRTOS: ARM Cortex-M4")
    
    # Специфичные флаги оптимизации для микроконтроллеров без ОС
    set(CMAKE_SYSROOT "")
    add_compile_options(
        -mcpu=cortex-m4
        -mthumb
        -mfloat-abi=hard
        -mfpu=fpv4-sp-d16
        -ffunction-sections
        -fdata-sections
        -nostartfiles
        --specs=nano.specs
        -Os # Оптимизация по размеру бинарника
    )
    add_link_options(
        -mcpu=cortex-m4
        -mthumb
        -mfloat-abi=hard
        -mfpu=fpv4-sp-d16
        -Wl,--gc-sections
        -Wl,-Map=${PROJECT_NAME}.map
    )
    add_compile_definitions(TARGET_LOW_LEVEL_MCU=1)

elseif(MCU_TARGET STREQUAL "CORTEX_A7")
    message(STATUS "Конфигурация сборки под RT-Preempt Linux: ARM Cortex-A7")
    
    # Флаги компиляции для процессоров прикладного уровня (например, Allwinner/NXP IMX6)
    add_compile_options(
        -mcpu=cortex-a7
        -mfpu=neon-vfpv4
        -mfloat-abi=hard
        -O2 # Высокая оптимизация по скорости
        -pthread
    )
    add_link_options(-pthread)
    add_compile_definitions(TARGET_APPLICATION_CPU=1)
endif()

# Ограничение статических предупреждений для встраиваемых систем
add_compile_options(-Wall -Wextra -Wpedantic -Wshadow -Wconversion)

# Определение исходного кода компонентов ядра
add_executable(${PROJECT_NAME}
    src/main.cpp
    src/NoveaAtomEngine.cpp
    src/CanJ1939Parser.cpp
    src/InerterDiagnostics.cpp
    src/MqttDispatcherGateway.cpp
)

# Установка путей включения заголовочных файлов
target_include_directories(${PROJECT_NAME} PRIVATE include)
