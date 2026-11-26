# Убрать бота из автозагрузки и остановить.
$vbs = Join-Path ([Environment]::GetFolderPath("Startup")) "{{SLUG}}-bot.vbs"
& (Join-Path $PSScriptRoot "stop.ps1") -Quiet
Remove-Item $vbs -ErrorAction SilentlyContinue
Write-Host "Бот остановлен и убран из автозагрузки."
