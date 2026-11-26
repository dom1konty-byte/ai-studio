@echo off
del /q "%~dp0stop.flag" 2>nul
start "" wscript.exe "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\{{SLUG}}-bot.vbs"
echo Бот запущен.
pause
