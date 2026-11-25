# Имя или Item ID устройства воспроизведения в SoundVolumeView.
$TvAudioName = "Samsung"
$TvDetectTimeoutSeconds = 120

. (Join-Path $PSScriptRoot 'mode-common.ps1')
try {
    $request = New-ModeRequest TV
    $tv = Find-TvMonitor -ToolPath $MultiMonitorTool -TvDisplayName $TvDisplayName -MonitorId (Get-ConfiguredMonitorId) -TimeoutSeconds $TvDetectTimeoutSeconds -RequestToken $request
    if (-not $tv) { return }

    Invoke-ModeLock {
        if (-not (Test-ModeRequest $request)) { return }
        $listener = Join-Path $PSScriptRoot 'hotkey-listener.ps1'
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$listener`" $request"
        [IO.File]::WriteAllText($ListenerFile, $request)
        try {
            if (-not (Set-TvDisplayConfiguration -ToolPath $MultiMonitorTool -TvMonitor $tv -StateDirectory $StateDirectory)) {
                throw 'Не удалось включить только выбранный телевизор.'
            }
        } catch {
            if (-not (Test-Path (Join-Path $StateDirectory 'pc-displays.cfg'))) { [IO.File]::Delete($ListenerFile) }
            throw
        }
        Set-ModeAudio $TvAudioName
        Enable-TvPowerPlan
        Start-Process 'steam://open/bigpicture'
        Write-ModeLog 'TV Mode: запрошен Steam Big Picture. Готово.'
    }
} catch {
    Write-ModeLog "TV Mode: ошибка: $_"
    exit 1
}
