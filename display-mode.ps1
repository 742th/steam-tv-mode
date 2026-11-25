# Уникальная часть Monitor Name телевизора в MultiMonitorTool.
$TvDisplayName = "Samsung"

function Invoke-MultiMonitorTool {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) {
        throw "MultiMonitorTool не найден: $ToolPath"
    }

    & $ToolPath @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "MultiMonitorTool завершился с кодом $LASTEXITCODE."
    }
}

function Get-MonitorRows {
    param([Parameter(Mandatory = $true)][string]$ToolPath)



    $CsvPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tv-mode-monitors-" + [guid]::NewGuid().ToString("N") + ".csv")
    try {
        Invoke-MultiMonitorTool -ToolPath $ToolPath -Arguments @("/scomma", $CsvPath)
        if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
            throw "MultiMonitorTool не создал список дисплеев."
        }

        $Rows = @(Import-Csv -LiteralPath $CsvPath -ErrorAction Stop)
        if ($Rows.Count -eq 0) {
            throw "MultiMonitorTool вернул пустой список дисплеев."
        }

        $ColumnNames = @($Rows[0].PSObject.Properties.Name)
        foreach ($Column in @("Name", "Monitor Name", "Monitor ID")) {
            if ($ColumnNames -notcontains $Column) {
                throw "В списке MultiMonitorTool отсутствует колонка '$Column'."
            }
        }

        return $Rows
    } finally {
        Remove-Item -LiteralPath $CsvPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-ActiveMonitorRecords {
    param([Parameter(Mandatory = $true)][string]$ToolPath)

    $Rows = @(Get-MonitorRows -ToolPath $ToolPath)
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $Screens = @([System.Windows.Forms.Screen]::AllScreens)
    $PrimaryDeviceName = [System.Windows.Forms.Screen]::PrimaryScreen.DeviceName
    $ActiveRecords = @()

    foreach ($Screen in $Screens) {
        $MatchingRows = @($Rows | Where-Object { $_.Name -ieq $Screen.DeviceName })
        if ($MatchingRows.Count -ne 1) {
            throw "Не удалось однозначно сопоставить активный экран '$($Screen.DeviceName)' с MultiMonitorTool."
        }

        $MonitorId = [string]$MatchingRows[0].'Monitor ID'
        if ([string]::IsNullOrWhiteSpace($MonitorId)) {
            throw "Для активного экрана '$($Screen.DeviceName)' MultiMonitorTool не вернул Monitor ID."
        }

        $ActiveRecords += [pscustomobject]@{
            DisplayName = [string]$Screen.DeviceName
            MonitorName = [string]$MatchingRows[0].'Monitor Name'
            MonitorId = $MonitorId
            X = $Screen.Bounds.X
            Y = $Screen.Bounds.Y
            IsPrimary = ($Screen.DeviceName -ieq $PrimaryDeviceName)
        }
    }

    return $ActiveRecords
}

function Test-MonitorIdSet {
    param(
        [string[]]$ExpectedMonitorIds,
        [string[]]$ActualMonitorIds
    )

    $Expected = @($ExpectedMonitorIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $Actual = @($ActualMonitorIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($Expected.Count -ne $Actual.Count) {
        return $false
    }

    $Differences = @(Compare-Object -ReferenceObject $Expected -DifferenceObject $Actual)
    return $Differences.Count -eq 0
}

function Wait-ForMonitorState {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [int]$TimeoutSeconds = 15,
        [string[]]$ExpectedMonitorIds,
        [string[]]$RequiredMonitorIds,
        [object[]]$ExpectedLayout,
        [string]$PrimaryMonitorId
    )

    $HasExpectedIds = $PSBoundParameters.ContainsKey("ExpectedMonitorIds")
    $HasRequiredIds = $PSBoundParameters.ContainsKey("RequiredMonitorIds")
    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        try {
            $Records = @(Get-ActiveMonitorRecords -ToolPath $ToolPath)
            $ActiveIds = @($Records | ForEach-Object { $_.MonitorId })
            $StateMatches = $true

            if ($HasExpectedIds -and -not (Test-MonitorIdSet -ExpectedMonitorIds $ExpectedMonitorIds -ActualMonitorIds $ActiveIds)) {
                $StateMatches = $false
            }

            if ($HasRequiredIds) {
                foreach ($RequiredId in $RequiredMonitorIds) {
                    if ($ActiveIds -notcontains $RequiredId) {
                        $StateMatches = $false
                        break
                    }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($PrimaryMonitorId)) {
                $PrimaryMatches = @($Records | Where-Object { $_.MonitorId -eq $PrimaryMonitorId -and $_.IsPrimary }).Count -eq 1
                if (-not $PrimaryMatches) {
                    $StateMatches = $false
                }
            }

            foreach ($Expected in $ExpectedLayout) {
                if (@($Records | Where-Object {
                    $_.MonitorId -eq $Expected.MonitorId -and $_.X -eq $Expected.X -and
                    $_.Y -eq $Expected.Y -and $_.IsPrimary -eq $Expected.IsPrimary
                }).Count -ne 1) { $StateMatches = $false }
            }

            if ($StateMatches) {
                return $Records
            }
        } catch {
            # Список дисплеев может быть временно недоступен во время смены режима.
        }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $Deadline)

    return $null
}

function Find-TvMonitor {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$TvDisplayName,
        [int]$TimeoutSeconds = 120
    )

    if ([string]::IsNullOrWhiteSpace($TvDisplayName)) {
        throw "Не задано имя телевизора в `$TvDisplayName."
    }

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Assert-CurrentModeRequest
        try {
            $Rows = @(Get-MonitorRows -ToolPath $ToolPath)
            $LastReadError = $null
        } catch {
            $LastReadError = $_.Exception.Message
            $Rows = @()
        }
        $Matches = @($Rows | Where-Object {
            $_.'Monitor ID' -and $_.Disconnected -ne 'Yes' -and $_.'Monitor Name' -and
            $_.'Monitor Name'.IndexOf($TvDisplayName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        if ($Matches.Count -gt 1) {
            throw "Найдено несколько дисплеев с именем '$TvDisplayName'. Укажи более точную часть имени телевизора."
        }
        if ($Matches.Count -eq 1) {
            return [pscustomobject]@{ MonitorId = $Matches[0].'Monitor ID'; MonitorName = $Matches[0].'Monitor Name' }
        }

        if ((Get-Date) -lt $Deadline) {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $Deadline)

    throw "Дисплей '$TvDisplayName' не найден за $TimeoutSeconds сек. $LastReadError Проверь Monitor Name в MultiMonitorTool."
}

function Get-DisplaySnapshot {
    param([Parameter(Mandatory = $true)][string]$StateDirectory)

    $ConfigPath = Join-Path $StateDirectory "pc-displays.cfg"
    $ManifestPath = Join-Path $StateDirectory "pc-displays.json"
    $HasConfig = Test-Path -LiteralPath $ConfigPath -PathType Leaf
    $HasManifest = Test-Path -LiteralPath $ManifestPath -PathType Leaf

    if ($HasConfig -ne $HasManifest) {
        throw "Найден неполный снимок конфигурации дисплеев. Файлы сохранены; режим экранов не изменён."
    }
    if (-not $HasConfig) {
        return $null
    }

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $MonitorIds = @($Manifest.ActiveMonitorIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $ConfigLength = (Get-Item -LiteralPath $ConfigPath -ErrorAction Stop).Length
    if ($MonitorIds.Count -eq 0 -or $ConfigLength -eq 0) {
        throw "Снимок конфигурации дисплеев повреждён. Файлы сохранены для диагностики."
    }

    return [pscustomobject]@{
        ConfigPath = $ConfigPath
        ManifestPath = $ManifestPath
        ActiveMonitorIds = $MonitorIds
        Layout = $Manifest.Layout
    }
}

function Save-PcDisplayConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [Parameter(Mandatory = $true)][object[]]$Records
    )

    if (-not (Test-Path -LiteralPath $StateDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $StateDirectory -Force -ErrorAction Stop | Out-Null
    }

    $ConfigPath = Join-Path $StateDirectory "pc-displays.cfg"
    $ManifestPath = Join-Path $StateDirectory "pc-displays.json"
    if ((Test-Path -LiteralPath $ConfigPath) -or (Test-Path -LiteralPath $ManifestPath)) {
        throw "Нельзя перезаписать незавершённый снимок конфигурации дисплеев."
    }

    $Suffix = [guid]::NewGuid().ToString("N")
    $TempConfigPath = Join-Path $StateDirectory ("pc-displays-" + $Suffix + ".tmp.cfg")
    $TempManifestPath = Join-Path $StateDirectory ("pc-displays-" + $Suffix + ".tmp.json")
    $SnapshotCommitted = $false
    $ConfigPromoted = $false
    $ManifestPromoted = $false

    try {
        Invoke-MultiMonitorTool -ToolPath $ToolPath -Arguments @("/SaveConfig", $TempConfigPath)
        if (-not (Test-Path -LiteralPath $TempConfigPath -PathType Leaf) -or (Get-Item -LiteralPath $TempConfigPath -ErrorAction Stop).Length -eq 0) {
            throw "MultiMonitorTool не сохранил конфигурацию дисплеев."
        }

        $Manifest = [pscustomobject]@{ ActiveMonitorIds = @($Records.MonitorId); Layout = @($Records | Select-Object MonitorId, X, Y, IsPrimary) }
        $Manifest | ConvertTo-Json -Compress | Set-Content -LiteralPath $TempManifestPath -Encoding UTF8 -ErrorAction Stop

        Move-Item -LiteralPath $TempConfigPath -Destination $ConfigPath -ErrorAction Stop | Out-Null
        $ConfigPromoted = $true
        Move-Item -LiteralPath $TempManifestPath -Destination $ManifestPath -ErrorAction Stop | Out-Null
        $ManifestPromoted = $true
        $SnapshotCommitted = $true
    } finally {
        Remove-Item -LiteralPath $TempConfigPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $TempManifestPath -Force -ErrorAction SilentlyContinue
        if (-not $SnapshotCommitted) {
            if ($ConfigPromoted) {
                Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
            }
            if ($ManifestPromoted) {
                Remove-Item -LiteralPath $ManifestPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Restore-SavedDisplayConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [string]$ModeName = "PC Mode"
    )

    try {
        $Snapshot = Get-DisplaySnapshot -StateDirectory $StateDirectory
        if (-not $Snapshot) {
            return $false
        }

        Invoke-MultiMonitorTool -ToolPath $ToolPath -Arguments @("/LoadConfig", $Snapshot.ConfigPath)
        $RestoredRecords = Wait-ForMonitorState -ToolPath $ToolPath -TimeoutSeconds 15 -ExpectedMonitorIds $Snapshot.ActiveMonitorIds -ExpectedLayout $Snapshot.Layout
        if (-not $RestoredRecords) {
            throw "После загрузки снимка активные дисплеи не совпали с исходной конфигурацией."
        }

        Remove-Item -LiteralPath $Snapshot.ConfigPath -Force -ErrorAction Stop
        Remove-Item -LiteralPath $Snapshot.ManifestPath -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "$($ModeName): не удалось восстановить дисплеи: $($_.Exception.Message)"
        return $false
    }
}

function Set-TvDisplayConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$TvDisplayName,
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [int]$TimeoutSeconds = 120
    )

    $SnapshotReady = $false
    try {
        $TvMonitor = Find-TvMonitor -ToolPath $ToolPath -TvDisplayName $TvDisplayName -TimeoutSeconds $TimeoutSeconds
        $InitialRecords = @(Get-ActiveMonitorRecords -ToolPath $ToolPath)
        $InitialIds = @($InitialRecords | ForEach-Object { $_.MonitorId } | Sort-Object -Unique)

        $Snapshot = Get-DisplaySnapshot -StateDirectory $StateDirectory
        if (-not $Snapshot) {
            if ($InitialIds -contains $TvMonitor.MonitorId -or $InitialIds.Count -eq 0) {
                throw "Для первого переключения включи в параметрах Windows только рабочие мониторы. ТВ оставь подключённым."
            }
            Save-PcDisplayConfiguration -ToolPath $ToolPath -StateDirectory $StateDirectory -Records $InitialRecords
            $Snapshot = Get-DisplaySnapshot -StateDirectory $StateDirectory
        }
        $SnapshotReady = $true

        Invoke-MultiMonitorTool -ToolPath $ToolPath -Arguments @("/enable", $TvMonitor.MonitorId)
        if (-not (Wait-ForMonitorState -ToolPath $ToolPath -TimeoutSeconds 15 -RequiredMonitorIds @($TvMonitor.MonitorId))) {
            throw "Телевизор не появился среди активных дисплеев."
        }

        $OtherMonitorIds = @($InitialRecords | Where-Object { $_.MonitorId -ne $TvMonitor.MonitorId } | ForEach-Object { $_.MonitorId } | Sort-Object -Unique)
        if ($OtherMonitorIds.Count -gt 0) {
            $DisableArguments = @("/disable") + $OtherMonitorIds
            Invoke-MultiMonitorTool -ToolPath $ToolPath -Arguments $DisableArguments
        }
        $TvOnlyRecords = Wait-ForMonitorState -ToolPath $ToolPath -TimeoutSeconds 15 -ExpectedMonitorIds @($TvMonitor.MonitorId)
        if (-not $TvOnlyRecords) {
            throw "После отключения остальных экранов активен не только телевизор."
        }

        Invoke-MultiMonitorTool -ToolPath $ToolPath -Arguments @("/SetPrimary", $TvMonitor.MonitorId)
        $PrimaryTvRecords = Wait-ForMonitorState -ToolPath $ToolPath -TimeoutSeconds 15 -ExpectedMonitorIds @($TvMonitor.MonitorId) -PrimaryMonitorId $TvMonitor.MonitorId
        if (-not $PrimaryTvRecords) {
            throw "Не удалось сделать телевизор основным дисплеем."
        }

        Write-Host "TV Mode: включён только телевизор '$($TvMonitor.MonitorName)'."
        return $true
    } catch {
        Write-Warning "TV Mode: не удалось переключить дисплеи: $($_.Exception.Message)"
        if ($SnapshotReady -and -not (Restore-SavedDisplayConfiguration -ToolPath $ToolPath -StateDirectory $StateDirectory -ModeName "TV Mode")) {
            Write-Warning "TV Mode: откат не подтверждён; снимок дисплеев сохранён для повторного восстановления."
        }
        return $false
    }
}

function Restore-PcDisplayConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$StateDirectory
    )

    try {
        $Snapshot = Get-DisplaySnapshot -StateDirectory $StateDirectory
    } catch {
        Write-Warning "PC Mode: не удалось прочитать снимок дисплеев: $($_.Exception.Message)"
        return $false
    }

    if ($Snapshot) {
        return Restore-SavedDisplayConfiguration -ToolPath $ToolPath -StateDirectory $StateDirectory
    }

    $Active = @(Get-ActiveMonitorRecords -ToolPath $ToolPath)
    if ($Active.Count -gt 0 -and @($Active | Where-Object {
        [string]::IsNullOrWhiteSpace($_.MonitorName) -or
        $_.MonitorName.IndexOf($TvDisplayName, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }).Count -eq 0) { return $true }
    Write-Warning "Нет сохранённой раскладки. Выбери рабочие мониторы в параметрах экрана Windows."
    return $false
}

function Assert-CurrentModeRequest {
    if ([Microsoft.Win32.Registry]::GetValue($RequestKey, 'Latest', '') -ne $RequestId) {
        throw "Получена новая команда переключения."
    }
}

function Invoke-ModeRequest {
    param([scriptblock]$Action)

    $RequestKey = 'HKEY_CURRENT_USER\Software\SteamTvMode'
    $RequestId = [guid]::NewGuid().ToString()
    [Microsoft.Win32.Registry]::SetValue($RequestKey, 'Latest', $RequestId)
    $Lock = [Threading.Mutex]::new($false, 'Local\SteamTvModeSwitch')
    $Owned = $false
    try {
        try { $Owned = $Lock.WaitOne() }
        catch [Threading.AbandonedMutexException] { $Owned = $true }
        Assert-CurrentModeRequest
        & $Action
    } finally {
        if ($Owned) { $Lock.ReleaseMutex() }
        $Lock.Dispose()
    }
}
