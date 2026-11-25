[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TvDisplayId
)

$ErrorActionPreference = 'Stop'

try {
    foreach ($file in 'tv-mode.ps1', 'pc-mode.ps1', 'hotkey-listener.ps1', 'mode-common.ps1', 'SoundVolumeView.exe') {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
            throw "Положи $file в папку $PSScriptRoot и повтори установку."
        }
    }

    $displays = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID |
        Where-Object { $_.Active -and $_.InstanceName } | Sort-Object InstanceName)
    if ($displays.Count -eq 0) {
        throw 'Windows не видит активных дисплеев. Включи телевизор и выбери «Расширить» через Win+P.'
    }

    if ($PSBoundParameters.ContainsKey('TvDisplayId')) {
        $display = $displays | Where-Object { $_.InstanceName -eq $TvDisplayId.Trim() } | Select-Object -First 1
        if (-not $display) {
            throw "Среди активных дисплеев нет устройства с InstanceName '$TvDisplayId'."
        }
    } else {
        Write-Host 'Выбери телевизор, на котором должен открываться Steam:'
        for ($i = 0; $i -lt $displays.Count; $i++) {
            $name = -join ($displays[$i].UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
            Write-Host ('{0}. {1}  [{2}]' -f ($i + 1), $name, $displays[$i].InstanceName)
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
    Set-Content -LiteralPath $idPath -Value $display.InstanceName -Encoding UTF8
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
    Write-Host "Телевизор: $($display.InstanceName)"
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
