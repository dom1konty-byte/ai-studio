# Обновить бота до последней версии из GitHub и перезапустить.
$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
Set-Location $proj
git pull
npm install --no-audit --no-fund
& (Join-Path $PSScriptRoot "stop.ps1") -Quiet
Remove-Item (Join-Path $PSScriptRoot "stop.flag") -ErrorAction SilentlyContinue
Start-Process wscript.exe -ArgumentList "`"$(Join-Path ([Environment]::GetFolderPath('Startup')) '{{SLUG}}-bot.vbs')`""
Write-Host "Бот обновлён и перезапущен."
