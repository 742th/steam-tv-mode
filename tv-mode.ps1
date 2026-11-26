# При входе в Windows этот скрипт переключает картинку и звук на ТВ и открывает Steam Big Picture.

# Настройки телевизора
# В SoundVolumeView найди устройство воспроизведения ТВ и скопируй его Item ID.
# Имя или Item ID устройства воспроизведения в SoundVolumeView.
$TvAudioName = "Samsung"

# Сколько секунд ждать телевизор, если он ещё просыпается.
$TvDetectTimeoutSeconds = 120

. (Join-Path $PSScriptRoot 'mode-common.ps1')
try {
    # Пока ищем телевизор, пользователь может отменить переход, запустив PC Mode.
    $settings = Get-ModeSettings
    if ($settings) { $TvAudioName = $settings.TvAudioId }
    $request = New-ModeRequest TV
    $tv = Find-TvMonitor -ToolPath $MultiMonitorTool -TvDisplayName $TvDisplayName -MonitorId (Get-ConfiguredMonitorId) -TimeoutSeconds $TvDetectTimeoutSeconds -RequestToken $request
    if (-not $tv) { return }

    Invoke-ModeLock {
        if (-not (Test-ModeRequest $request)) { return }
        # Заранее включаем Ctrl+Alt+P, чтобы можно было вернуться на ПК даже при ошибке со звуком.
        $listener = Join-Path $PSScriptRoot 'hotkey-listener.ps1'
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$listener`" $request"
        [IO.File]::WriteAllText($ListenerFile, $request)
        try {
            if (-not (Set-TvDisplayConfiguration -ToolPath $MultiMonitorTool -TvMonitor $tv -StateDirectory $StateDirectory)) {
                throw 'Не удалось включить только выбранный телевизор.'
            }
        } catch {
            if (-not ((Test-Path (Join-Path $StateDirectory 'pc-displays')) -or (Test-Path (Join-Path $StateDirectory 'pc-displays.cfg')))) { [IO.File]::Delete($ListenerFile) }
            throw
        }
        Set-ModeAudio $TvAudioName
        try { Enable-TvPowerPlan } catch { Write-ModeLog "TV Mode: не удалось включить план питания: $_" }
        Start-Process 'steam://open/bigpicture'
        Write-ModeLog 'TV Mode: запрошен Steam Big Picture. Готово.'
    }
} catch {
    Write-ModeLog "TV Mode: ошибка: $_"
    exit 1
}
