@echo off
:: Right-click this file and select "Run as administrator"
:: OR open an elevated PowerShell and run the .ps1 directly.

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo ERROR: This script must be run as administrator.
    echo Right-click this file and choose "Run as administrator".
    pause
    exit /b 1
)

echo [PresentMon Benchmark Suite]
echo Starting GPU benchmark - this will take about 4 minutes...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_presentmon_benchmark.ps1"

echo.
echo Done. Reports saved to: %~dp0reports\presentmon\
pause
