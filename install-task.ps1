# ================================================================
# Регистрация автозапуска в Windows Task Scheduler.
# ЗАПУСКАЕТСЯ ОДИН РАЗ, ОТ ИМЕНИ АДМИНИСТРАТОРА.
# После этого tv-mode.ps1 будет стартовать сам при входе в Windows.
# ================================================================

# --- НАСТРОЙКИ ---------------------------------------------------
$ScriptPath = "C:\Tools\tv-mode.ps1"
# -----------------------------------------------------------------

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Скрипт не найден: $ScriptPath. Положи tv-mode.ps1 по этому пути или поменяй `$ScriptPath в install-task.ps1."
    exit 1
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

Register-ScheduledTask `
    -TaskName "TV Gaming Mode" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -RunLevel Highest `
    -Force

Write-Host ""
Write-Host "Готово. Задача 'TV Gaming Mode' зарегистрирована."
Write-Host "Проверить: Пуск -> 'Планировщик заданий' -> Библиотека планировщика -> TV Gaming Mode."
Write-Host "Удалить: Unregister-ScheduledTask -TaskName 'TV Gaming Mode' -Confirm:`$false"
