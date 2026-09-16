# Sweep clk90off then clk90on with the same bidirectional L3 closeloop.
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
if (-not $env:XILINX_VITIS) { throw "set XILINX_VITIS to the Vitis install root" }
$xsct = Join-Path $env:XILINX_VITIS "bin\xsct.bat"
$bits = @(
    (Join-Path $repo "bitstream_output\system_top_clk90off.bit"),
    (Join-Path $repo "bitstream_output\system_top_clk90on.bit")
)
$summary = @()
foreach ($bit in $bits) {
    if (-not (Test-Path $bit)) { throw "missing $bit" }
    Write-Host "==== RUN $bit ===="
    $log = Join-Path $repo ("vivado_l3_sweep_{0}.log" -f [IO.Path]::GetFileNameWithoutExtension($bit))
    & $xsct scripts/xsct_l3_closeloop.tcl $bit 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { Write-Host "WARN: xsct exit $LASTEXITCODE for $bit" }
    $a = Select-String -Path $log -Pattern "^RESULT_A:" | Select-Object -Last 1
    $b = Select-String -Path $log -Pattern "^RESULT_B:" | Select-Object -Last 1
    $p = Select-String -Path $log -Pattern "^PASS:" | Select-Object -Last 1
    $summary += [pscustomobject]@{
        Bit = [IO.Path]::GetFileName($bit)
        A   = $(if ($a) { $a.Line } else { "MISSING" })
        B   = $(if ($b) { $b.Line } else { "MISSING" })
        Pass = $(if ($p) { $p.Line } else { "MISSING" })
    }
}
Write-Host ""
Write-Host "==== SWEEP SUMMARY ===="
$summary | ForEach-Object {
    Write-Host ("--- {0} ---" -f $_.Bit)
    Write-Host $_.A
    Write-Host $_.B
    Write-Host $_.Pass
}
Write-Host "INFO: L3 sweep done"
