@echo off
rem Запускает бота и перезапускает его, если он упал. Остановить: windows\stop.cmd
chcp 65001 >nul
cd /d "%~dp0.."
del /q "windows\stop.flag" 2>nul
:loop
if exist "windows\stop.flag" goto :eof
call npm start >> bot.log 2>&1
if exist "windows\stop.flag" goto :eof
timeout /t 10 /nobreak >nul
goto loop
