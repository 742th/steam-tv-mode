param([Parameter(Mandatory)][string]$ListenerToken)

. (Join-Path $PSScriptRoot 'mode-common.ps1')
try {
    if (-not (Test-Listener $ListenerToken)) { return }
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;

public static class SteamTvModeHotkeyNative
{
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int virtualKey);
}
"@

    $pcMode = Join-Path $PSScriptRoot 'pc-mode.ps1'
    while (Test-Listener $ListenerToken) {
        for ($i = 0; $i -lt 10; $i++) {
            if (([SteamTvModeHotkeyNative]::GetAsyncKeyState(0x11) -lt 0) -and
                ([SteamTvModeHotkeyNative]::GetAsyncKeyState(0x12) -lt 0) -and
                ([SteamTvModeHotkeyNative]::GetAsyncKeyState(0x50) -lt 0)) {
                & $pcMode -ExpectedListener $ListenerToken
                exit $LASTEXITCODE
            }
            Start-Sleep -Milliseconds 50
        }
    }
} catch {
    Write-ModeLog "Горячая клавиша: $_"
    exit 1
}
