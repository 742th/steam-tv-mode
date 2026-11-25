
function Get-CimInstance {
    param($Namespace, $ClassName)
    if ($ClassName -ne 'WmiMonitorID') { throw "Unexpected WMI class: $ClassName" }
    $fixture.Reads++
    $id = if ($fixture.CancelOnWait -and $fixture.Reads -eq 1) { 'DISPLAY\SAM\OTHER' } else { $fixture.Id }
    if ($fixture.WrongTopology -and $fixture.Reads -ge 2) { $id = 'DISPLAY\SAM\OTHER' }
    [pscustomobject]@{ Active = $true; InstanceName = $id; UserFriendlyName = [char[]]'Samsung'; ManufacturerName = [char[]]'SAM' }
}
function Get-Date {
    param([string]$Format)
    $now = [datetime]::Now
    if ($fixture.WrongTopology -and $fixture.Reads -ge 2) { $now = $now.AddSeconds(20) }
    if ($Format) { $now.ToString($Format) } else { $now }
}
function Start-Sleep {
    if ($fixture.CancelOnWait -and $fixture.Reads -eq 1) {
        & (Join-Path $fixture.Temp 'pc-mode.ps1')
    }
}
function Start-Process {
    param($FilePath, $ArgumentList, $WindowStyle)
    $fixture.Calls.Add($FilePath)
}
function Get-Process { param($Name); return $null }
function Invoke-ModeNative {
    param($Executable, [string[]]$Arguments)
    switch -Regex ($Executable) {
        'DisplaySwitch' { $fixture.Calls.Add($Arguments[0]) }
        'powercfg' {
            switch ($Arguments[0]) {
                '/getactivescheme' { "Power Scheme GUID: $($fixture.Scheme) (fixture)" }
                '/setactive' {
                    $fixture.Scheme = if ($Arguments[1] -eq 'SCHEME_MIN') { $fixture.High } else { $Arguments[1] }
                }
                default { throw "Unexpected power command: $Arguments" }
            }
        }
        'SoundVolumeView' {
            switch ($Arguments[0]) {
                '/SetDefault' { $fixture.Audio = $Arguments[1] }
                '/GetColumnValue' {
                    if ($Arguments[1] -like 'DefaultRenderDevice*') { $fixture.Audio } else { "id-$($Arguments[1])" }
                }
                default { throw "Unexpected audio command: $Arguments" }
            }
        }
        default { throw "Unexpected native tool: $Executable" }
    }
}
