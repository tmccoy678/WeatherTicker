@echo off
setlocal
set "APPDIR=%LOCALAPPDATA%\ThreeSourceWeatherTicker\App"

if not exist "%APPDIR%" mkdir "%APPDIR%"
copy /Y "%~dp0WeatherTicker.ps1" "%APPDIR%\WeatherTicker.ps1" >nul
copy /Y "%~dp0Weather Ticker.cmd" "%APPDIR%\Weather Ticker.cmd" >nul
copy /Y "%~dp0Configure Weather Ticker.cmd" "%APPDIR%\Configure Weather Ticker.cmd" >nul
copy /Y "%~dp0Open Location Roster.cmd" "%APPDIR%\Open Location Roster.cmd" >nul
copy /Y "%~dp0locations-template.csv" "%APPDIR%\locations-template.csv" >nul
copy /Y "%~dp0README.txt" "%APPDIR%\README.txt" >nul
copy /Y "%~dp0START HERE.txt" "%APPDIR%\START HERE.txt" >nul
copy /Y "%~dp0LICENSE" "%APPDIR%\LICENSE" >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$desktop=[Environment]::GetFolderPath('Desktop'); $shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Weather Ticker.lnk')); $shortcut.TargetPath=(Join-Path $env:LOCALAPPDATA 'ThreeSourceWeatherTicker\App\Weather Ticker.cmd'); $shortcut.WorkingDirectory=(Join-Path $env:LOCALAPPDATA 'ThreeSourceWeatherTicker\App'); $shortcut.Description='NOAA, Weather Underground, and AccuWeather desktop ticker'; $shortcut.Save()"

echo.
echo Installed. A Weather Ticker shortcut is now on the Desktop.
echo The ticker will open now with Bassfield already selected.
echo.
call "%APPDIR%\Weather Ticker.cmd"
endlocal
