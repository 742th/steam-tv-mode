$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ("steam mode tests " + [guid]::NewGuid())
$oldAppData = $env:LOCALAPPDATA
$oldWinDir = $env:WINDIR
function Assert-True ($condition, $message) {
    if (-not $condition) { throw $message }
}
try {
    New-Item -ItemType Directory $temp | Out-Null
    $env:LOCALAPPDATA = $temp
    $env:WINDIR = $temp
    foreach ($file in Get-ChildItem $root -Filter '*.ps1') {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        Assert-True ([BitConverter]::ToString($bytes, 0, 3) -eq 'EF-BB-BF') "$($file.Name) needs UTF-8 BOM for Windows PowerShell"
        $errorsFound = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errorsFound)
        Assert-True (-not $errorsFound) "$($file.Name): $errorsFound"
        Copy-Item -LiteralPath $file.FullName -Destination $temp
    }
    # Override only OS interactions in a disposable copy. Leave synchronization and state on disk real.
    $common = Join-Path $temp 'mode-common.ps1'
    Add-Content -LiteralPath $common -Value (Get-Content (Join-Path $PSScriptRoot 'windows-mocks.ps1') -Raw) -Encoding UTF8
    $global:fixture = @{
        Id = 'DISPLAY\TV\01'; Reads = 0; CancelOnWait = $false
        Scheme = 'e22d939c-32dc-4383-8985-cf936ff97268'
        High = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; Calls = [Collections.Generic.List[string]]::new()
        Temp = $temp; Seconds = 0; Active = @('pc1', 'pc2')
    }
    New-Item -ItemType File (Join-Path $temp 'SoundVolumeView.exe') | Out-Null
    Set-Content (Join-Path $temp 'tv-display.id') $fixture.Id
    $tv = Join-Path $temp 'tv-mode.ps1'
    $pc = Join-Path $temp 'pc-mode.ps1'
    $original = $fixture.Scheme

    $fixture.CancelOnWait = $true
    & $tv
    Assert-True ($fixture.Reads -ge 1) 'TV did not query for a monitor'
    Assert-True ($fixture.Audio -eq 'id-Realtek') 'PC request was not applied while TV was waiting'
    Assert-True (-not $fixture.Calls.Contains('/enable')) 'Unrelated monitor or canceled request activated TV'
    Assert-True (-not $fixture.Calls.Contains('steam://open/bigpicture')) 'Canceled TV request opened Steam'
    Assert-True ($fixture.Scheme -eq $original) 'Standalone PC request changed the power scheme'
    $fixture.CancelOnWait = $false
    $fixture.Calls.Clear()
    & $tv
    Assert-True ($fixture.Scheme -eq $fixture.High -and $fixture.Calls.Contains('/enable')) 'TV did not activate display and power'
    Assert-True ($fixture.Calls.Contains('steam://open/bigpicture')) 'TV did not open Big Picture'
    $listenerFile = Join-Path $temp 'steam-tv-mode/listener'
    $firstListener = [IO.File]::ReadAllText($listenerFile)
    & $tv
    $fixture.Calls.Clear()
    & $pc -ExpectedListener $firstListener
    Assert-True ($fixture.Calls.Count -eq 0 -and $fixture.Scheme -eq $fixture.High) 'An obsolete listener canceled a newer TV session'
    & $pc
    Assert-True ($fixture.Scheme -eq $original) 'Repeated TV activation overwrote the previous power scheme'
    Assert-True (($fixture.Active -join ',') -eq 'pc1,pc2' -and $fixture.Calls.Contains('/LoadConfig')) 'PC did not restore both displays'
    # An unintended output topology must switch straight back to PC before touching audio or Steam.
    $fixture.WrongTopology = $true
    $fixture.Reads = 0
    $fixture.Calls.Clear()
    & $tv
    Assert-True ($LASTEXITCODE -eq 1) 'Unexpected external topology was reported as success'
    Assert-True ($fixture.Calls.Contains('/LoadConfig') -and $fixture.Calls.Contains('/enable')) 'Wrong output was not rolled back'
    Assert-True (-not (Test-Path -LiteralPath $listenerFile)) 'Listener still active after fallback to PC'
    Assert-True (-not $fixture.Calls.Contains('steam://open/bigpicture')) 'Steam opened on the wrong monitor'
    $fixture.WrongTopology = $false

    # An interrupted staging directory is invisible. Published snapshots are retired together.
    $state = Join-Path $temp 'steam-tv-mode'
    $orphan = [IO.Directory]::CreateDirectory((Join-Path $state 'pending-interrupted'))
    [IO.File]::WriteAllText((Join-Path $orphan.FullName 'pc-displays.cfg'), 'partial')
    $fixture.FailHigh = $true
    $fixture.Calls.Clear()
    @{ MonitorId = $fixture.Id; TvAudioId = 'tv-configured'; PcAudioId = 'pc-configured' } |
        ConvertTo-Json | Set-Content (Join-Path $temp 'mode-settings.json') -Encoding UTF8
    & $tv
    Assert-True ($fixture.Audio -eq 'id-tv-configured') 'TV ignored configured audio'
    Assert-True ($fixture.Calls.Contains('steam://open/bigpicture')) 'Power failure blocked Steam'
    Assert-True (Test-Path (Join-Path $state 'pc-displays/pc-displays.cfg')) 'Snapshot was not published'
    & $pc
    Assert-True ($fixture.Audio -eq 'id-pc-configured') 'PC ignored configured audio'
    Assert-True (-not (Test-Path (Join-Path $state 'pc-displays'))) 'Snapshot was not retired'
    $fixture.FailHigh = $false
    $log = Get-Content (Join-Path $state 'mode.log') -Raw
    Assert-True ($log.Contains('power plan unavailable')) 'Lost power failure detail'
    Assert-True ($log.Contains('После отключения остальных экранов')) 'Lost topology failure detail'

    # A missing audio tool must report failure while still restoring the power plan.
    & $tv
    Remove-Item -LiteralPath (Join-Path $temp 'SoundVolumeView.exe')
    & $pc
    Assert-True ($LASTEXITCODE -eq 1) 'Missing audio tool was reported as success'
    Assert-True ($fixture.Scheme -eq $original) 'PC abandoned power restoration after an audio failure'
    $log = Get-Content (Join-Path $temp 'steam-tv-mode/mode.log') -Raw
    Assert-True ($log.Contains('SoundVolumeView.exe')) 'Log did not identify the failed audio tool'

    Write-Host 'PASS: encoding, parsing, canceled TV request, unrelated display, TV/TV/PC, power restoration, logging and partial failure'
} finally {
    $env:LOCALAPPDATA = $oldAppData
    $env:WINDIR = $oldWinDir
    Remove-Variable fixture -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
exit 0
