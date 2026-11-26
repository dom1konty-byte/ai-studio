# Остановить бота (до следующего включения компьютера или windows\start.cmd).
param([switch]$Quiet)
$proj = Split-Path -Parent $PSScriptRoot
New-Item -ItemType File -Force -Path (Join-Path $PSScriptRoot "stop.flag") | Out-Null
$pidFile = Join-Path $proj "bot.pid"
if (Test-Path $pidFile) {
  $botPid = [int](Get-Content $pidFile)
  Stop-Process -Id $botPid -Force -ErrorAction SilentlyContinue
  Remove-Item $pidFile -ErrorAction SilentlyContinue
}
if (-not $Quiet) { Write-Host "Бот остановлен." }
