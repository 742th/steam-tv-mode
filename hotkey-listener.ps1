# Глобальная горячая клавиша возврата из TV Mode в PC Mode.

$StateDirectory = Join-Path $env:LOCALAPPDATA "steam-tv-mode"
$PcModeMarker = Join-Path $StateDirectory "pc-mode.active"
$Mutex = [System.Threading.Mutex]::new($false, 'Local\SteamTvModeHotkeyListener')
$OwnsMutex = $false

try {
    try {
        $OwnsMutex = $Mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $OwnsMutex = $true
    }

    if (-not $OwnsMutex -or (Test-Path -LiteralPath $PcModeMarker)) {
        return
    }

    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;

public static class SteamTvModeHotkeyNative
{
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int virtualKey);
}
"@

    $PcModeScript = Join-Path $PSScriptRoot "pc-mode.ps1"
    $WasPressed = $false

    while (-not (Test-Path -LiteralPath $PcModeMarker)) {
        $IsPressed = ([SteamTvModeHotkeyNative]::GetAsyncKeyState(0x11) -lt 0) -and
            ([SteamTvModeHotkeyNative]::GetAsyncKeyState(0x12) -lt 0) -and
            ([SteamTvModeHotkeyNative]::GetAsyncKeyState(0x50) -lt 0)

        if ($IsPressed -and -not $WasPressed) {
            $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PcModeScript`""
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList $Arguments
            break
        }

        $WasPressed = $IsPressed
        Start-Sleep -Milliseconds 50
    }
} finally {
    if ($OwnsMutex) {
        $Mutex.ReleaseMutex()
    }
    $Mutex.Dispose()
}
