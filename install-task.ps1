# Запусти при установке или обновлении из обычного PowerShell под пользователем Steam.
# Скрипт запоминает выбранный телевизор и настраивает запуск TV Mode при входе в Windows.
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TvDisplayId,
    [string]$TvAudioId,
    [string]$PcAudioId
)

$ErrorActionPreference = 'Stop'

try {
    foreach ($file in 'tv-mode.ps1', 'pc-mode.ps1', 'hotkey-listener.ps1', 'mode-common.ps1', 'SoundVolumeView.exe', 'display-mode.ps1', 'MultiMonitorTool.exe') {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
            throw "Положи $file в папку $PSScriptRoot и повтори установку."
        }
    }

    . (Join-Path $PSScriptRoot 'mode-common.ps1')
    $displays = @(Get-MonitorRows -ToolPath (Join-Path $PSScriptRoot 'MultiMonitorTool.exe') |
        Where-Object { $_.Disconnected -ne 'Yes' -and $_.'Monitor ID' } | Sort-Object 'Monitor ID')
    if ($displays.Count -eq 0) {
        throw 'MultiMonitorTool не видит подключённых дисплеев. Проверь подключение телевизора.'
    }

    if ($PSBoundParameters.ContainsKey('TvDisplayId')) {
        $display = $displays | Where-Object { $_.'Monitor ID' -eq $TvDisplayId.Trim() } | Select-Object -First 1
        if (-not $display) {
            throw "Среди подключённых дисплеев нет устройства с Monitor ID '$TvDisplayId'."
        }
    } else {
        Write-Host 'Выбери телевизор, на котором должен открываться Steam:'
        for ($i = 0; $i -lt $displays.Count; $i++) {
            $name = $displays[$i].'Monitor Name'
            Write-Host ('{0}. {1}  [{2}]' -f ($i + 1), $name, $displays[$i].'Monitor ID')
        }
        $index = 0
        $answer = Read-Host 'Номер телевизора'
        if (-not [int]::TryParse($answer, [ref]$index) -or $index -lt 1 -or $index -gt $displays.Count) {
            throw 'Некорректный номер. Запусти установку снова.'
        }
        $display = $displays[$index - 1]
    }

    $devices = @(Get-PlaybackDevices)
    if (-not $devices.Count) { throw 'SoundVolumeView не нашёл устройства воспроизведения.' }
    function Select-AudioId([string]$Label, [string]$Id) {
        if ($Id) {
            if ($devices.'Item ID' -notcontains $Id) { throw "Нет аудиоустройства '$Id'." }
            return $Id
        }
        for ($i = 0; $i -lt $devices.Count; $i++) {
            Write-Host ('{0}. {1} ({2}) [{3}]' -f ($i + 1), $devices[$i].Name, $devices[$i].'Device Name', $devices[$i].'Item ID')
        }
        $index = 0
        if (-not [int]::TryParse((Read-Host "Номер устройства для $Label"), [ref]$index) -or $index -lt 1 -or $index -gt $devices.Count) {
            throw 'Некорректный номер аудиоустройства.'
        }
        return $devices[$index - 1].'Item ID'
    }
    $settingsJson = [ordered]@{
        MonitorId = $display.'Monitor ID'
        TvAudioId = Select-AudioId 'ТВ' $TvAudioId
        PcAudioId = Select-AudioId 'ПК' $PcAudioId
    } | ConvertTo-Json
    $scriptPath = Join-Path $PSScriptRoot 'tv-mode.ps1'
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powershell `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    $configPath = Join-Path $PSScriptRoot 'mode-settings.json'
    $tempPath = "$configPath.$([guid]::NewGuid()).tmp"
    $backupPath = "$tempPath.bak"
    try {
        [IO.File]::WriteAllText($tempPath, $settingsJson)
        if ([IO.File]::Exists($configPath)) {
            [IO.File]::Replace($tempPath, $configPath, $backupPath)
        } else {
            [IO.File]::Move($tempPath, $configPath)
        }
        try {
            Register-ScheduledTask -TaskName 'TV Gaming Mode' -Action $action -Trigger $trigger `
                -Principal $principal -Settings $settings -Force | Out-Null
        } catch {
            if ([IO.File]::Exists($backupPath)) {
                [IO.File]::Copy($backupPath, $configPath, $true)
                [IO.File]::Delete($backupPath)
            } else {
                [IO.File]::Delete($configPath)
            }
            throw
        }
        [IO.File]::Delete($backupPath)
    } finally {
        [IO.File]::Delete($tempPath)
    }

    Write-Host "Готово. Задача 'TV Gaming Mode' зарегистрирована для $user."
    Write-Host "Телевизор: $($display.'Monitor ID')"
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
