@echo off
REM Relink netsec_l3 using Vitis GNU tools. Set XILINX_VITIS (e.g. <install>/Vitis/2020.1).
setlocal
if "%XILINX_VITIS%"=="" (
  echo ERROR: set XILINX_VITIS to the Vitis install root
  exit /b 2
)
set ROOT=%~dp0..
set GCC=%XILINX_VITIS%\gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-gcc.exe
set OBJCOPY=%XILINX_VITIS%\gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-objcopy.exe
set INC=%ROOT%\firmware\vitis_ws\netsec_plat\export\netsec_plat\sw\netsec_plat\standalone_domain\bspinclude\include
set LIB=%ROOT%\firmware\vitis_ws\netsec_plat\export\netsec_plat\sw\netsec_plat\standalone_domain\bsplib\lib
set SRC=%ROOT%\firmware
set APP=%ROOT%\firmware\vitis_ws\netsec_l3
copy /Y "%SRC%\netsec_l3_gem3.c" "%APP%\src\netsec_l3_gem3.c"
if errorlevel 1 exit /b 1
copy /Y "%SRC%\crt0_ocm.S" "%APP%\src\crt0_ocm.S"
if errorlevel 1 exit /b 1
copy /Y "%SRC%\lscript_ocm.ld" "%APP%\src\lscript.ld"
if errorlevel 1 exit /b 1
"%GCC%" -Wall -O0 -g3 -c -fmessage-length=0 -I"%INC%" -o "%APP%\Debug\src\netsec_l3_gem3.o" "%APP%\src\netsec_l3_gem3.c"
if errorlevel 1 exit /b 1
"%GCC%" -c -o "%APP%\Debug\src\crt0_ocm.o" "%APP%\src\crt0_ocm.S"
if errorlevel 1 exit /b 1
"%GCC%" -nostartfiles -Wl,-T -Wl,%APP%\src\lscript.ld -L"%LIB%" -Wl,--build-id=none -Wl,-u -Wl,MMUTableL0 -o "%APP%\Debug\netsec_l3.elf" "%APP%\Debug\src\crt0_ocm.o" "%APP%\Debug\src\netsec_l3_gem3.o" -Wl,--start-group,-lxil,-lgcc,-lc,--end-group
if errorlevel 1 exit /b 1
copy /Y "%APP%\Debug\netsec_l3.elf" "%SRC%\netsec_l3.elf"
"%OBJCOPY%" -O binary "%SRC%\netsec_l3.elf" "%SRC%\netsec_l3.bin"
echo ELF_OK
