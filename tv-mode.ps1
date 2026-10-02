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

# Часть имени телевизора в списке дисплеев Windows.
$TvDisplayName = "Samsung"

# Максимум секунд ждать, пока Windows увидит телевизор.
$TvDetectTimeoutSeconds = 120

# -----------------------------------------------------------------

Write-Host "TV Mode: ищу дисплей с именем '$TvDisplayName'..."
$TvDetectionDeadline = (Get-Date).AddSeconds($TvDetectTimeoutSeconds)
$TvDisplay = $null
while (-not $TvDisplay -and (Get-Date) -lt $TvDetectionDeadline) {
    $TvDisplay = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue |
        Where-Object {
            $FriendlyName = -join ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            $ManufacturerName = -join ($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            $ConfiguredNameMatches = "$FriendlyName $ManufacturerName" -like "*$TvDisplayName*"
            $SamsungFallbackMatches = $FriendlyName -like "*Samsung*" -or $ManufacturerName -eq "SAM"
            $_.Active -and ($ConfiguredNameMatches -or $SamsungFallbackMatches)
        } |
        Select-Object -First 1

    if (-not $TvDisplay) {
        Start-Sleep -Seconds 2
    }
}

if (-not $TvDisplay) {
    Write-Warning "TV Mode: дисплей '$TvDisplayName' или Samsung не найден за $TvDetectTimeoutSeconds сек. Настройки не изменены."
    exit 1
}

$TvFriendlyName = -join ($TvDisplay.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
Write-Host "TV Mode: найден дисплей '$TvFriendlyName'."

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
