[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TvDisplayId
)

$ErrorActionPreference = 'Stop'

try {
    foreach ($file in 'tv-mode.ps1', 'pc-mode.ps1', 'hotkey-listener.ps1', 'mode-common.ps1', 'SoundVolumeView.exe', 'display-mode.ps1', 'MultiMonitorTool.exe') {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
            throw "Положи $file в папку $PSScriptRoot и повтори установку."
        }
    }

    . (Join-Path $PSScriptRoot 'display-mode.ps1')
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

    $scriptPath = Join-Path $PSScriptRoot 'tv-mode.ps1'
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powershell `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    $idPath = Join-Path $PSScriptRoot 'tv-display.id'
    $oldId = $null
    if ([IO.File]::Exists($idPath)) {
        $oldId = [IO.File]::ReadAllBytes($idPath)
    }
    Set-Content -LiteralPath $idPath -Value $display.'Monitor ID' -Encoding UTF8
    try {
        Register-ScheduledTask -TaskName 'TV Gaming Mode' -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
    } catch {
        if ($null -ne $oldId) {
            [IO.File]::WriteAllBytes($idPath, $oldId)
        } else {
            Remove-Item -LiteralPath $idPath
        }
        throw
    }

    Write-Host "Готово. Задача 'TV Gaming Mode' зарегистрирована для $user."
    Write-Host "Телевизор: $($display.'Monitor ID')"
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
