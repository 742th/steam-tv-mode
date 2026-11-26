# Возвращает рабочие мониторы, звук и план питания. Steam остаётся открытым.
# Запускается ярлыком или по Ctrl+Alt+P во время игры.
param([string]$ExpectedListener)

# Настройки звука на ПК
# Выбери в SoundVolumeView колонки или наушники, на которые должен вернуться звук.
# Имя или Item ID устройства воспроизведения в SoundVolumeView.
$PcAudioName = "Realtek"

. (Join-Path $PSScriptRoot 'mode-common.ps1')
try {
    $settings = Get-ModeSettings
    if ($settings) { $PcAudioName = $settings.PcAudioId }
    $request = New-ModeRequest PC $ExpectedListener
    if (-not $request) { return }
    Invoke-ModeLock {
        if (-not (Test-ModeRequest $request)) { return }
        # При отказе одного шага продолжаем восстанавливать остальные настройки.
        $failures = @()
        foreach ($step in @(
            {
                if (-not (Restore-PcDisplayConfiguration -ToolPath $MultiMonitorTool -StateDirectory $StateDirectory -MonitorId (Get-ConfiguredMonitorId))) {
                    throw 'Не удалось восстановить раскладку мониторов.'
                }
                [IO.File]::Delete($ListenerFile)
            }
            { Set-ModeAudio $PcAudioName }
            {
                if (Get-Process -Name steam -ErrorAction SilentlyContinue) {
                    Start-Process 'steam://close/bigpicture'
                    Write-ModeLog 'Запрошен выход из Steam Big Picture.'
                }
            }
            { Restore-PcPowerPlan }
        )) {
            try { & $step } catch {
                $failures += $_.Exception.Message
                Write-ModeLog "PC Mode: $_"
            }
        }
        if ($failures.Count) { throw ($failures -join '; ') }
        Write-ModeLog 'PC Mode: готово.'
    }
} catch {
    Write-ModeLog "PC Mode: ошибка: $_"
    exit 1
}
