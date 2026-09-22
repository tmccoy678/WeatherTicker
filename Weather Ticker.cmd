@echo off
setlocal
start "Three-Source Weather Ticker" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0WeatherTicker.ps1"
endlocal
