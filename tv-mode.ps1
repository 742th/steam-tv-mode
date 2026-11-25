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

# --- НАСТРОЙКИ (поменяй под себя) --------------------------------

# Часть имени аудио-устройства ТВ.
# Как узнать: правой кнопкой по иконке звука в трее -> "Звуки"
# -> вкладка "Воспроизведение". Найди устройство телека, скопируй
# кусок имени (например "Samsung" или "TV" или "AV Receiver").
$TvAudioName = "Samsung"

# Путь к SoundVolumeView.exe (см. README, шаг про NirSoft).
$SoundVolumeView = "C:\Tools\SoundVolumeView.exe"

# Путь к MultiMonitorTool.exe (см. README).
$MultiMonitorTool = "C:\Tools\MultiMonitorTool.exe"

# Максимум секунд ждать, пока Windows увидит телевизор.
$TvDetectTimeoutSeconds = 120

# -----------------------------------------------------------------

. (Join-Path $PSScriptRoot "display-mode.ps1")
Invoke-ModeRequest {
    Write-Host "TV Mode: ищу телевизор '$TvDisplayName' в MultiMonitorTool..."
    if (-not (Set-TvDisplayConfiguration -ToolPath $MultiMonitorTool -TvDisplayName $TvDisplayName -StateDirectory $StateDirectory -TimeoutSeconds $TvDetectTimeoutSeconds)) {
        throw "TV Mode: переход не выполнен."
    }

    Remove-Item -LiteralPath $PcModeMarker -Force -ErrorAction SilentlyContinue
    Assert-CurrentModeRequest
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
}
