$ErrorActionPreference = 'Stop'
$StateDirectory = Join-Path $env:LOCALAPPDATA 'steam-tv-mode'
[IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
$RequestFile = Join-Path $StateDirectory 'request'
$PowerPlanFile = Join-Path $StateDirectory 'original-power-scheme'
$ListenerFile = Join-Path $StateDirectory 'listener'
$LogFile = Join-Path $StateDirectory 'mode.log'

# Автозапуск, ярлык и горячая клавиша могут сработать одновременно.
# Эта блокировка даёт одному скрипту закончить переключение, прежде чем начнёт другой.
function Invoke-ModeLock([scriptblock]$Action) {
    $mutex = [Threading.Mutex]::new($false, 'Local\SteamTvModeTransition')
    try {
        try { $null = $mutex.WaitOne() } catch [Threading.AbandonedMutexException] {}
        try { & $Action } finally { $mutex.ReleaseMutex() }
    } finally { $mutex.Dispose() }
}

function Write-ModeLog([string]$Message) {
    Write-Host $Message
    Invoke-ModeLock {
        Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value "$(Get-Date -Format o) [$PID] $Message"
    }
}

function New-ModeRequest([string]$Mode, [string]$ExpectedListener) {
    Invoke-ModeLock {
        if ($ExpectedListener -and -not (Test-Listener $ExpectedListener)) { return }
        $token = "$Mode-$([guid]::NewGuid())"
        [IO.File]::WriteAllText($RequestFile, $token)
        $token
    }
}

function Test-ModeRequest([string]$Token) {
    Invoke-ModeLock { [IO.File]::ReadAllText($RequestFile) -eq $Token }
}

function Test-Listener([string]$Token) {
    Invoke-ModeLock {
        [IO.File]::Exists($ListenerFile) -and [IO.File]::ReadAllText($ListenerFile) -eq $Token
    }
}

function Invoke-ModeNative([string]$Program, [string[]]$Arguments) {
    $output = & $Program @Arguments | Out-String
    if ($LASTEXITCODE -ne 0) { throw "$Program $Arguments (exit $LASTEXITCODE): $output" }
    $output.Trim()
}

. (Join-Path $PSScriptRoot 'display-mode.ps1')
$MultiMonitorTool = Join-Path $PSScriptRoot 'MultiMonitorTool.exe'
$SettingsPath = Join-Path $PSScriptRoot 'mode-settings.json'
function Get-ModeSettings {
    if ([IO.File]::Exists($SettingsPath)) {
        Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

function Get-PlaybackDevices {
    $csv = Join-Path ([IO.Path]::GetTempPath()) ("steam-audio-" + [guid]::NewGuid() + ".csv")
    try {
        $null = Invoke-ModeNative (Join-Path $PSScriptRoot 'SoundVolumeView.exe') @('/scomma', $csv, '/Columns', 'Type,Direction,Name,Device Name,Item ID')
        Import-Csv -LiteralPath $csv | Where-Object { $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and $_.'Item ID' }
    } finally {
        [IO.File]::Delete($csv)
    }
}

function Get-ConfiguredMonitorId {
    $settings = Get-ModeSettings
    if ($settings) { return $settings.MonitorId }
    $path = Join-Path $PSScriptRoot 'tv-display.id'
    if ([IO.File]::Exists($path)) { [IO.File]::ReadAllText($path).Trim() }
}

function Set-ModeAudio([string]$Name) {
    $tool = Join-Path $PSScriptRoot 'SoundVolumeView.exe'
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Не найден $tool" }
    # После смены экрана HDMI-звук может появиться чуть позже изображения.
    $deadline = (Get-Date).AddSeconds(5)
    do {
        $device = Invoke-ModeNative $tool @('/GetColumnValue', $Name, 'Item ID')
        if ($device) { break }
        if ((Get-Date) -ge $deadline) { throw "Не найдено аудиоустройство '$Name'." }
        Start-Sleep -Milliseconds 500
    } while ($true)
    $null = Invoke-ModeNative $tool @('/SetDefault', $device, 'all')
    foreach ($role in 'DefaultRenderDevice', 'DefaultRenderDeviceMulti', 'DefaultRenderDeviceComm') {
        if ((Invoke-ModeNative $tool @('/GetColumnValue', $role, 'Item ID')) -ne $device) {
            throw "Аудиоустройство '$Name' не назначено для $role."
        }
    }
    Write-ModeLog "Аудиоустройство: $Name"
}

function Enable-TvPowerPlan {
    # Запоминаем исходный план только при первом входе. Повторный запуск TV Mode должен его сохранить.
    if (-not [IO.File]::Exists($PowerPlanFile)) {
        $current = Invoke-ModeNative powercfg.exe @('/getactivescheme')
        if ($current -notmatch '[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}') {
            throw "Не удалось определить текущую схему питания: $current"
        }
        [IO.File]::WriteAllText("$PowerPlanFile.tmp", $Matches[0])
        [IO.File]::Move("$PowerPlanFile.tmp", $PowerPlanFile)
    }
    $null = Invoke-ModeNative powercfg.exe @('/setactive', 'SCHEME_MIN')
    Write-ModeLog 'Включена производительная схема питания.'
}

function Restore-PcPowerPlan {
    if ([IO.File]::Exists($PowerPlanFile)) {
        $original = [guid]::Parse([IO.File]::ReadAllText($PowerPlanFile))
        $null = Invoke-ModeNative powercfg.exe @('/setactive', $original.ToString())
        [IO.File]::Delete($PowerPlanFile)
        Write-ModeLog "Восстановлена схема питания $original."
    }
}
