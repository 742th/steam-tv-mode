# Exercise task construction and config rollback without registering a Windows task.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$folder = Join-Path ([IO.Path]::GetTempPath()) ("steam install " + [guid]::NewGuid())
$installer = Join-Path $folder 'install-task.ps1'
$idFile = Join-Path $folder 'mode-settings.json'
$tvId = 'DISPLAY\TV\01'
$registered = [Collections.ArrayList]::new()

function Get-MonitorRows {
    [pscustomobject]@{ Disconnected = 'No'; 'Monitor ID' = $tvId; 'Monitor Name' = 'TV' }
}
function Get-PlaybackDevices {
    [pscustomobject]@{ 'Item ID' = 'tv-sound' }
    [pscustomobject]@{ 'Item ID' = 'pc-sound' }
}
function New-ScheduledTaskAction { param($Execute, $Argument); $PSBoundParameters }
function New-ScheduledTaskTrigger { param([switch]$AtLogOn, $User); $PSBoundParameters }
function New-ScheduledTaskPrincipal { param($UserId, $LogonType, $RunLevel); $PSBoundParameters }
function New-ScheduledTaskSettingsSet {
    param([switch]$StartWhenAvailable, [switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries)
    $PSBoundParameters
}
function Register-ScheduledTask {
    param($TaskName, $Action, $Trigger, $Principal, $Settings, [switch]$Force)
    if ($failRegistration) { throw 'Simulated scheduler failure' }
    [void]$registered.Add($PSBoundParameters)
}

try {
    [void][IO.Directory]::CreateDirectory($folder)
    Copy-Item -LiteralPath (Join-Path $root 'install-task.ps1') -Destination $installer
    & $installer -TvAudioId tv-sound -PcAudioId pc-sound -TvDisplayId $tvId 2>$null
    if ($LASTEXITCODE -ne 1 -or (Test-Path $idFile)) { throw 'Incomplete installation was accepted' }

    if ([Environment]::OSVersion.Platform -eq 'Win32NT') {
        foreach ($name in 'tv-mode.ps1','pc-mode.ps1','mode-common.ps1','hotkey-listener.ps1','SoundVolumeView.exe','MultiMonitorTool.exe','display-mode.ps1') {
            [IO.File]::WriteAllText((Join-Path $folder $name), '')
        }
        & $installer -TvDisplayId 'DISPLAY\OTHER' 2>$null
        if ($LASTEXITCODE -ne 1 -or (Test-Path $idFile)) { throw 'Unknown monitor was accepted' }

        $failRegistration = $false
        & $installer -TvAudioId tv-sound -PcAudioId pc-sound -TvDisplayId $tvId
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $task = $registered[0]
        if ($registered.Count -ne 1 -or $task.Principal.RunLevel -ne 'Limited' -or
            $task.Principal.LogonType -ne 'Interactive' -or $task.Principal.UserId -ne $user -or
            -not $task.Trigger.AtLogOn -or $task.Trigger.User -ne $user -or
            $task.Action.Argument -notlike '*-File "*"' -or (Get-Content $idFile -Raw | ConvertFrom-Json).MonitorId -ne $tvId -or
            (Get-Content $idFile -Raw | ConvertFrom-Json).PcAudioId -ne 'pc-sound') {
            throw 'Invalid principal, logon trigger, action or persisted display'
        }

        [IO.File]::WriteAllText($idFile, 'previous')
        $failRegistration = $true
        & $installer -TvAudioId tv-sound -PcAudioId pc-sound -TvDisplayId $tvId 2>$null
        if ($LASTEXITCODE -ne 1 -or [IO.File]::ReadAllText($idFile) -ne 'previous') {
            throw 'Registration failure did not restore the previous configuration'
        }
        Write-Host 'PASS: limited interactive task, display selection and rollback'
    }
    Write-Host 'PASS: incomplete installation rejected'
} finally {
    if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
}
exit 0
