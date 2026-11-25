# Имя или Item ID устройства воспроизведения в SoundVolumeView.
$TvAudioName = "Samsung"
$TvDetectTimeoutSeconds = 120

. (Join-Path $PSScriptRoot 'mode-common.ps1')
try {
    $request = New-ModeRequest TV
    $displayId = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tv-display.id')).Trim()
    if (-not $displayId) { throw 'Укажите телевизор с помощью install-task.ps1.' }
    Write-ModeLog "TV Mode: ожидаю $displayId."
    $deadline = (Get-Date).AddSeconds($TvDetectTimeoutSeconds)
    do {
        if (-not (Test-ModeRequest $request)) { return }
        $tv = Get-TvMonitors | Where-Object { $_.InstanceName -eq $displayId }
        if ($tv) { break }
        if ((Get-Date) -ge $deadline) { throw "Телевизор не обнаружен за $TvDetectTimeoutSeconds с." }
        Start-Sleep -Seconds 2
    } while ($true)

    Invoke-ModeLock {
        if (-not (Test-ModeRequest $request)) { return }
        $listener = Join-Path $PSScriptRoot 'hotkey-listener.ps1'
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$listener`" $request"
        [IO.File]::WriteAllText($ListenerFile, $request)
        try {
            Set-ModeDisplay external
            $deadline = (Get-Date).AddSeconds(10)
            do {
                $active = @(Get-TvMonitors | Where-Object { $_.Active })
                if ($active.Count -eq 1 -and $active[0].InstanceName -eq $displayId) { break }
                if ((Get-Date) -ge $deadline) { throw 'Windows активировала другой дисплей.' }
                Start-Sleep -Milliseconds 500
            } while ($true)
        } catch {
            Set-ModeDisplay internal
            [IO.File]::Delete($ListenerFile)
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
