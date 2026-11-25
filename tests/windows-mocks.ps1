
function Get-MonitorRows {
    param($ToolPath)
    $fixture.Reads++
    $id = if ($fixture.CancelOnWait) { 'other' } else { $fixture.Id }
    [pscustomobject]@{ 'Monitor ID' = $id; 'Monitor Name' = 'Samsung'; Disconnected = 'No' }
}
function Get-ActiveMonitorRecords {
    param($ToolPath)
    foreach ($id in $fixture.Active) {
        [pscustomobject]@{ MonitorId = $id; MonitorName = $id; IsPrimary = $id -eq $fixture.Active[0]; X = if ($id -eq 'pc2') { 1920 } else { 0 }; Y = 0 }
    }
}
function Invoke-MultiMonitorTool {
    param($ToolPath, $Arguments)
    $fixture.Calls.Add($Arguments[0])
    switch ($Arguments[0]) {
        '/SaveConfig' { [IO.File]::WriteAllLines($Arguments[1], [string[]]$fixture.Active) }
        '/LoadConfig' { $fixture.Active = @([IO.File]::ReadAllLines($Arguments[1])) }
        '/enable' { $fixture.Active = @($fixture.Active | Where-Object { $_ -ne $Arguments[1] }) + $Arguments[1] }
        '/disable' { if (-not $fixture.WrongTopology) { $fixture.Active = @($fixture.Active | Where-Object { $_ -notin $Arguments[1..($Arguments.Count - 1)] }) } }
        '/SetPrimary' { $fixture.Active = @($Arguments[1]) + @($fixture.Active | Where-Object { $_ -ne $Arguments[1] }) }
        default { throw "Unexpected display command: $Arguments" }
    }
}
function Get-Date {
    param([string]$Format)
    $now = [datetime]::Now.AddSeconds($fixture.Seconds)
    if ($Format) { $now.ToString($Format) } else { $now }
}
function Start-Sleep {
    $fixture.Seconds += 2
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
