# L3 dual-port: program PL (100 kHz / xsct), AN, run GEM3 ELF, dump
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
if (-not $env:XILINX_VIVADO) { throw "set XILINX_VIVADO to the Vivado install root" }
if (-not $env:XILINX_VITIS) { throw "set XILINX_VITIS to the Vitis install root" }
$vivado = Join-Path $env:XILINX_VIVADO "bin\vivado.bat"
$xsct   = Join-Path $env:XILINX_VITIS "bin\xsct.bat"

# Full program+run if PL is blank; 100 kHz + rst -system is the reliable path
& $xsct scripts/xsct_fpga_then_l3.tcl
if ($LASTEXITCODE -ne 0) { throw "xsct_fpga_then_l3 failed" }
Start-Sleep -Seconds 3
& $vivado -mode batch -source scripts/hw_l3_dump.tcl -log vivado_l3_dump.log -journal vivado_l3_dump.jou
Write-Host "INFO: L3 dual-port sequence done"
