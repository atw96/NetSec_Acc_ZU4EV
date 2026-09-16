# Questa UVM notes (ModelSim SE-64 2020.4)

## Status — ✅ 已本机编译并运行

`tb_netsec_uvm` smoke test：

```text
UVM_INFO ... Running test netsec_smoke_test...
UVM_ERROR : 0 / UVM_FATAL : 0
$finish @ 5044 ns
```

日志：`tb/uvm_env/questa_run.log`

## How to run

From repo root:

```bat
C:\modeltech64_2020.4\win64\vsim.exe -c -do tb/uvm_env/run_questa.do
```

## DPI workaround

System `C:\MinGW\bin\gcc.exe` is **32-bit**, so ModelSim cannot build `export_tramp.dll`
(x86_64 `%rax` assembler errors). The `.do` script therefore uses:

- `-sv_lib C:/modeltech64_2020.4/uvm-1.2/win64/uvm_dpi` — vendor prebuilt DPI imports
- `-nodpiexports` — skip trampoline that needs a 64-bit GCC

Installing mingw-w64 and putting it first on `PATH` allows dropping `-nodpiexports`
if SV→C DPI exports are later required.
