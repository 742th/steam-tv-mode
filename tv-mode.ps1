# ================================================================
# TV Gaming Mode
# Переключает картинку и звук на телек, запускает Steam Big Picture.
# Этот скрипт запускается автоматически при входе в Windows.
# ================================================================

$StateDirectory = Join-Path $env:LOCALAPPDATA "steam-tv-mode"
$PcModeMarker = Join-Path $StateDirectory "pc-mode.active"
if (-not (Test-Path $StateDirectory)) {
    New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
}
Remove-Item -LiteralPath $PcModeMarker -Force -ErrorAction SilentlyContinue

# --- НАСТРОЙКИ (поменяй под себя) --------------------------------

# Часть имени аудио-устройства ТВ.
# Как узнать: правой кнопкой по иконке звука в трее -> "Звуки"
# -> вкладка "Воспроизведение". Найди устройство телека, скопируй
# кусок имени (например "Samsung" или "TV" или "AV Receiver").
$TvAudioName = "Samsung"

# Путь к SoundVolumeView.exe (см. README, шаг про NirSoft).
$SoundVolumeView = "C:\Tools\SoundVolumeView.exe"

# Сколько секунд ждать перед переключением — пока беспроводной
# ресивер и телек проснутся и Windows увидит внешний дисплей.
# Если телек не успевает — увеличь. Если телек включается быстро — уменьши.
$WaitSeconds = 20

# -----------------------------------------------------------------

Write-Host "TV Mode: жду $WaitSeconds сек, пока телек проснётся..."
Start-Sleep -Seconds $WaitSeconds

Write-Host "TV Mode: переключаю дисплей на телек..."
# /external = картинка только на телек
# /extend   = расширить рабочий стол на телек
# /clone    = дублировать
# /internal = только монитор ПК
& "$env:WINDIR\System32\DisplaySwitch.exe" /external
Start-Sleep -Seconds 4

Write-Host "TV Mode: переключаю звук на телек ($TvAudioName)..."
if (Test-Path $SoundVolumeView) {
    & $SoundVolumeView /SetDefault $TvAudioName all
} else {
    Write-Warning "SoundVolumeView не найден по пути $SoundVolumeView — звук не переключён. См. README."
}

Write-Host "TV Mode: включаю high-performance power plan..."
powercfg /setactive SCHEME_MIN

Write-Host "TV Mode: запускаю Steam Big Picture..."
Start-Process "steam://open/bigpicture"

Write-Host "TV Mode: включаю горячую клавишу Ctrl+Alt+P..."
$HotkeyListenerScript = Join-Path $PSScriptRoot "hotkey-listener.ps1"
$HotkeyListenerArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$HotkeyListenerScript`""
Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList $HotkeyListenerArguments

Write-Host "TV Mode: готово."
