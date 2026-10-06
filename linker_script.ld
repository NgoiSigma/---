/* Архитектура: ARM Cortex-M4 Core */
ENTRY(Reset_Handler)

/* Спецификация физической карты памяти устройства */
MEMORY
{
  FLASH (rx)      : ORIGIN = 0x08000000, LENGTH = 512K  /* Общая память программ и ядра */
  EEPROM_LOG (r)  : ORIGIN = 0x08080000, LENGTH = 64K   /* Сектор хранения логов сбоев */
  RAM (xrw)       : ORIGIN = 0x20000000, LENGTH = 128K  /* Оперативная память стека и данных */
}

/* Определение вершины стека в конце оперативной памяти RAM */
_estack = ORIGIN(RAM) + LENGTH(RAM);

/* Минимальные объемы для кучи и стека (статическая валидация компилятора) */
_Min_Left_SCHED_HEAP  = 0x200;  /* 512 байт резерва кучи (динамическая куча запрещена) */
_Min_Left_ISR_STACK   = 0x800;  /* 2 Кб под прерывания контура КЗ и SPI */

SECTIONS
{
  /* Секция векторов прерываний Cortex-M4 (Высший приоритет размещения во Flash) */
  .isr_vector :
  {
    . = ALIGN(4);
    KEEP(*(.isr_vector))
    . = ALIGN(4);
  } > FLASH

  /* Исполняемый код программы и математические константы ядра FDL */
  .text :
  {
    . = ALIGN(4);
    *(.text)           /* Код функций */
    *(.text*)          /* Дополнительные сборочные секции кода */
    *(.glue_7)         /* glue arm to thumb code */
    *(.glue_7t)        /* glue thumb to arm code */
    *(.eh_frame)

    KEEP (*(.init))
    KEEP (*(.fini))

    . = ALIGN(4);
    _etext = .;        /* Глобальный маркер окончания секции кода */
  } > FLASH

  /* Константные данные (Read-Only Data) */
  .rodata :
  {
    . = ALIGN(4);
    *(.rodata)
    *(.rodata*)
    . = ALIGN(4);
  } > FLASH

  /* Секция ARM таблиц для раскрутки стека при сбоях */
  .ARM.extab   : { *(.ARM.extab* .gnu.linkonce.armextab.*) } > FLASH
  .ARM.exidx   : { *(.ARM.exidx* .gnu.linkonce.armexidx.*) } > FLASH

  /* Используется системным стартап-файлом для инициализации секции данных в RAM из Flash */
  _sidata = LOADADDR(.data);

  /* Секция инициализированных данных ядра, загружаемая в RAM */
  .data : 
  {
    . = ALIGN(4);
    _sdata = .;        /* Начало данных в RAM */
    *(.data)
    *(.data*)
    . = ALIGN(4);
    _edata = .;        /* Конец данных в RAM */
  } > RAM AT > FLASH

  /* Секция неинициализированных данных (BSS) - обнуляется при старте процессора */
  .bss :
  {
    . = ALIGN(4);
    _sbss = .;         
    __bss_start__ = _sbss;
    *(.bss)
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;         
    __bss_end__ = _ebss;
  } > RAM

  /* Жесткое резервирование статического адресного пространства под логер ошибок */
  .eeprom_log_section (NOLOAD) :
  {
    . = ALIGN(4);
    KEEP(*(.eeprom_log_section))
    . = ALIGN(4);
  } > EEPROM_LOG

  /* Проверка линкером наличия достаточного места для стека и кучи в RAM */
  ._user_heap_stack :
  {
    . = ALIGN(8);
    PROVIDE ( end = . );
    PROVIDE ( _end = . );
    . = . + _Min_Left_SCHED_HEAP;
    . = . + _Min_Left_ISR_STACK;
    . = ALIGN(8);
  } > RAM

  /* Удаление отладочной информации из финального бинарника прошивки */
  /DISCARD/ :
  {
    libc.a ( * )
    libm.a ( * )
    libgcc.a ( * )
  }
}
