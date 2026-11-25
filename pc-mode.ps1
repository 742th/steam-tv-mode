# ================================================================
# Back to PC Mode
# Возвращает конфигурацию экранов и звук, выходит из Big Picture, оставляя Steam открытым.
# Запускай руками (ярлык на рабочем столе или хоткей), когда наигрался.
# ================================================================

$StateDirectory = Join-Path $env:LOCALAPPDATA "steam-tv-mode"
if (-not (Test-Path $StateDirectory)) {
    New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
}
$PcModeMarker = Join-Path $StateDirectory "pc-mode.active"

# --- НАСТРОЙКИ ---------------------------------------------------

# Часть имени твоего обычного аудио-устройства (наушники / колонки монитора).
# Как узнать — так же, как в tv-mode.ps1.
$PcAudioName = "Realtek"

$SoundVolumeView = "C:\Tools\SoundVolumeView.exe"
$MultiMonitorTool = "C:\Tools\MultiMonitorTool.exe"

# -----------------------------------------------------------------

. (Join-Path $PSScriptRoot "display-mode.ps1")
Invoke-ModeRequest {
    Write-Host "PC Mode: восстанавливаю конфигурацию дисплеев..."
    $Restored = Restore-PcDisplayConfiguration -ToolPath $MultiMonitorTool -StateDirectory $StateDirectory

    Write-Host "PC Mode: переключаю звук на $PcAudioName..."
    if (Test-Path $SoundVolumeView) {
        & $SoundVolumeView /SetDefault $PcAudioName all
    }

    Write-Host "PC Mode: выхожу из Steam Big Picture..."
    if (Get-Process -Name steam -ErrorAction SilentlyContinue) {
        Start-Process "steam://close/bigpicture"
    }

    Write-Host "PC Mode: возвращаю balanced power plan..."
    powercfg /setactive SCHEME_BALANCED

    if (-not $Restored) { throw "PC Mode: восстановление экранов не подтверждено." }
    New-Item -ItemType File -Path $PcModeMarker -Force | Out-Null
    Write-Host "PC Mode: готово."
}
