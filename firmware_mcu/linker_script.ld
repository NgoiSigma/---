/* Linker script for NOVEYA ATOM ARM Cortex-A7/M4 */
ENTRY(Reset_Handler)

MEMORY
{
  FLASH (rx)      : ORIGIN = 0x08000000, LENGTH = 512K
  RAM (xrw)       : ORIGIN = 0x20000000, LENGTH = 128K
  
  /* Изолированный сектор для энергонезависимого Ring Buffer на 128 записей */
  EEPROM_LOG (rw) : ORIGIN = 0x08080000, LENGTH = 4K 
}

SECTIONS
{
  .isr_vector :
  {
    . = ALIGN(4);
    KEEP(*(.isr_vector))
    . = ALIGN(4);
  } >FLASH

  .text :
  {
    . = ALIGN(4);
    *(.text)
    *(.text*)
    *(.rodata)
    *(.rodata*)
    . = ALIGN(4);
    _etext = .;
  } >FLASH

  .data : AT ( _etext )
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data)
    *(.data*)
    . = ALIGN(4);
    _edata = .;
  } >RAM

  .bss :
  {
    . = ALIGN(4);
    _sbss = .;
    *(.bss)
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } >RAM

  /* Выделенная секция для модуля EepromStorageLogger */
  .eeprom_log_section (NOLOAD) :
  {
    . = ALIGN(4);
    *(.eeprom_log_data)
    . = ALIGN(4);
  } >EEPROM_LOG
}
