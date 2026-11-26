# Установка бота на этот компьютер: токен, пакеты, автозагрузка, запуск.
# Запуск: двойной клик по windows\setup.cmd
param([string]$Token = "", [switch]$NoStart)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$proj = Split-Path -Parent $PSScriptRoot
Set-Location $proj

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "Нужен Node.js: https://nodejs.org (кнопка LTS). Установи и запусти setup.cmd снова."
  exit 1
}

if ($Token) {
  Set-Content -Path .env -Value "BOT_TOKEN=$Token" -Encoding ascii
} elseif (-not (Test-Path .env) -or (Read-Host "Токен уже сохранён. Заменить? (y/N)") -eq "y") {
  $sec = Read-Host "Вставь токен бота от @BotFather (символы не видны — это нормально)" -AsSecureString
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  Set-Content -Path .env -Value "BOT_TOKEN=$plain" -Encoding ascii
}

Write-Host "Ставлю пакеты (1–2 минуты)..."
npm install --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw "npm install не удался" }

$startup = [Environment]::GetFolderPath("Startup")
$vbs = Join-Path $startup "{{SLUG}}-bot.vbs"
$cmd = Join-Path $PSScriptRoot "run-bot.cmd"
$line = 'CreateObject("WScript.Shell").Run """' + $cmd + '""", 0, False'
Set-Content -Path $vbs -Value $line -Encoding Unicode
Write-Host "Автозагрузка: $vbs"

& (Join-Path $PSScriptRoot "stop.ps1") -Quiet
if (-not $NoStart) {
  Remove-Item (Join-Path $PSScriptRoot "stop.flag") -ErrorAction SilentlyContinue
  Start-Process wscript.exe -ArgumentList "`"$vbs`""
  Write-Host "Готово: бот запущен и будет стартовать сам при включении компьютера. Журнал: $proj\bot.log"
}
