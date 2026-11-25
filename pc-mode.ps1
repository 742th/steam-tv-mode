param([string]$ExpectedListener)

# Имя или Item ID устройства воспроизведения в SoundVolumeView.
$PcAudioName = "Realtek"

. (Join-Path $PSScriptRoot 'mode-common.ps1')
try {
    $request = New-ModeRequest PC $ExpectedListener
    if (-not $request) { return }
    Invoke-ModeLock {
        if (-not (Test-ModeRequest $request)) { return }
        # При отказе одного шага продолжаем восстанавливать остальные настройки.
        $failures = @()
        foreach ($step in @(
            { Set-ModeDisplay internal }
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
