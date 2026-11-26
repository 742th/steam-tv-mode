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
            $lastReadError = $_.Exception.Message
            # Список дисплеев может быть временно недоступен во время смены режима.
        }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $Deadline)

    if ($lastReadError) { Write-ModeLog "Последняя ошибка чтения дисплеев: $lastReadError" }
    return $null
}

function Find-TvMonitor {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$TvDisplayName,
        [int]$TimeoutSeconds = 120,
        [string]$MonitorId,
        [string]$RequestToken
    )

    if ([string]::IsNullOrWhiteSpace($TvDisplayName)) {
        throw "Не задано имя телевизора в `$TvDisplayName."
    }

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ($RequestToken -and -not (Test-ModeRequest $RequestToken)) { return }
        try {
            $Rows = @(Get-MonitorRows -ToolPath $ToolPath)
            $LastReadError = $null
        } catch {
            $LastReadError = $_.Exception.Message
            $Rows = @()
        }
        $Matches = @($Rows | Where-Object {
            if (-not $_.'Monitor ID' -or $_.Disconnected -eq 'Yes') { return $false }
            if ($MonitorId) { return $_.'Monitor ID' -eq $MonitorId }
            $_.'Monitor Name' -and $_.'Monitor Name'.IndexOf($TvDisplayName, [StringComparison]::OrdinalIgnoreCase) -ge 0
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

    $target = if ($MonitorId) { $MonitorId } else { $TvDisplayName }
    throw "Дисплей '$target' не найден за $TimeoutSeconds сек. $LastReadError Проверь Monitor Name в MultiMonitorTool."
}

function Get-DisplaySnapshot {
    param([Parameter(Mandatory = $true)][string]$StateDirectory)

    $directory = Join-Path $StateDirectory 'pc-displays'
    $legacyRestored = Join-Path $StateDirectory 'legacy-displays-restored'
    if ([IO.File]::Exists($legacyRestored)) {
        [IO.File]::Delete((Join-Path $StateDirectory 'pc-displays.cfg'))
        [IO.File]::Delete((Join-Path $StateDirectory 'pc-displays.json'))
        [IO.File]::Delete($legacyRestored)
    }
    $legacy = -not [IO.Directory]::Exists($directory)
    if ($legacy) { $directory = $StateDirectory }
    $ConfigPath = Join-Path $directory "pc-displays.cfg"
    $ManifestPath = Join-Path $directory "pc-displays.json"
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
        Legacy = $legacy
        ConfigPath = $ConfigPath
        ManifestPath = $ManifestPath
        ActiveMonitorIds = $MonitorIds
        Layout = $Manifest.Layout
    }
}

# Перед игрой сохраняем расположение рабочих мониторов и отмечаем, какой экран основной.
function Save-PcDisplayConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [Parameter(Mandatory = $true)][object[]]$Records
    )

    if (-not (Test-Path -LiteralPath $StateDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $StateDirectory -Force -ErrorAction Stop | Out-Null
    }

    $directory = Join-Path $StateDirectory 'pc-displays'
    $staging = Join-Path $StateDirectory ("pending-" + [guid]::NewGuid())
    [IO.Directory]::CreateDirectory($staging) | Out-Null
    $TempConfigPath = Join-Path $staging 'pc-displays.cfg'
    $TempManifestPath = Join-Path $staging 'pc-displays.json'
    try {
        Invoke-MultiMonitorTool -ToolPath $ToolPath -Arguments @("/SaveConfig", $TempConfigPath)
        if (-not (Test-Path -LiteralPath $TempConfigPath -PathType Leaf) -or (Get-Item -LiteralPath $TempConfigPath -ErrorAction Stop).Length -eq 0) {
            throw "MultiMonitorTool не сохранил конфигурацию дисплеев."
        }

        $Manifest = [pscustomobject]@{ ActiveMonitorIds = @($Records.MonitorId); Layout = @($Records | Select-Object MonitorId, X, Y, IsPrimary) }
        $Manifest | ConvertTo-Json -Compress | Set-Content -LiteralPath $TempManifestPath -Encoding UTF8 -ErrorAction Stop

        [IO.Directory]::Move($staging, $directory)
    } finally {
        if ([IO.Directory]::Exists($staging)) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Загружаем раскладку и сверяем её с исходной. Если экраны ещё не вернулись на свои места,
# сохранённые файлы понадобятся для следующей попытки.
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

        if ($Snapshot.Legacy) {
            $marker = Join-Path $StateDirectory 'legacy-displays-restored'
            [IO.File]::WriteAllText($marker, '')
            [IO.File]::Delete($Snapshot.ConfigPath)
            [IO.File]::Delete($Snapshot.ManifestPath)
            [IO.File]::Delete($marker)
        } else {
            $retired = Join-Path $StateDirectory ("restored-" + [guid]::NewGuid())
            [IO.Directory]::Move((Split-Path $Snapshot.ConfigPath), $retired)
            Remove-Item -LiteralPath $retired -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        Write-ModeLog "$($ModeName): не удалось восстановить дисплеи: $($_.Exception.Message)"
        return $false
    }
}

function Set-TvDisplayConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][object]$TvMonitor,
        [Parameter(Mandatory = $true)][string]$StateDirectory
    )

    $SnapshotReady = $false
    try {
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

        # Телевизор уже показывает изображение. Теперь можно отключить остальные экраны.
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
        Write-ModeLog "TV Mode: не удалось переключить дисплеи: $($_.Exception.Message)"
        if ($SnapshotReady -and -not (Restore-SavedDisplayConfiguration -ToolPath $ToolPath -StateDirectory $StateDirectory -ModeName "TV Mode")) {
            Write-ModeLog "TV Mode: откат не подтверждён; снимок дисплеев сохранён для повторного восстановления."
        }
        return $false
    }
}

function Restore-PcDisplayConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [string]$MonitorId
    )

    try {
        $Snapshot = Get-DisplaySnapshot -StateDirectory $StateDirectory
    } catch {
        Write-ModeLog "PC Mode: не удалось прочитать снимок дисплеев: $($_.Exception.Message)"
        return $false
    }

    if ($Snapshot) {
        return Restore-SavedDisplayConfiguration -ToolPath $ToolPath -StateDirectory $StateDirectory
    }

    $Active = @(Get-ActiveMonitorRecords -ToolPath $ToolPath)
    if ($Active.Count -gt 0 -and @($Active | Where-Object {
        if ($MonitorId) { return $_.MonitorId -eq $MonitorId }
        [string]::IsNullOrWhiteSpace($_.MonitorName) -or
        $_.MonitorName.IndexOf($TvDisplayName, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }).Count -eq 0) { return $true }
    Write-ModeLog "Нет сохранённой раскладки. Выбери рабочие мониторы в параметрах экрана Windows."
    return $false
}
