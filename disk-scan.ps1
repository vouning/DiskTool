<#
===========================================================================
  СКАНЕР ДИСКОВ — быстрая проверка работоспособности накопителей
===========================================================================
  Что делает:
    * SMART-здоровье и статус физических дисков
    * ошибки чтения/записи, температура, износ
    * тома и заполненность (где мало места — видно сразу)
    * разделы и обзор дисков
    * при запуске БЕЗ прав администратора — упрощённый отчёт через WMI
      (раньше чем ныть о правах — сканер уже работает)

  Запуск:
    powershell -ExecutionPolicy Bypass -File disk-scan.ps1
  Рекомендуется от администратора (SMART виден полностью).
===========================================================================
#>

$ErrorActionPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$isAdmin = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "Компьютер: $env:COMPUTERNAME | Пользователь: $env:USERNAME | Админ: $isAdmin" -ForegroundColor Cyan
Write-Host ""

if ($isAdmin) {
    # ---- 1. Физические диски + SMART (быстрые CIM-запросы) ----
    Write-Host "=== ФИЗИЧЕСКИЕ ДИСКИ (SMART) ===" -ForegroundColor Green
    $health = foreach ($d in Get-PhysicalDisk) {
        $rc = Get-StorageReliabilityCounter -PhysicalDisk $d
        [PSCustomObject]@{
            Диск         = $d.FriendlyName
            Тип          = $d.MediaType
            Здоровье     = $d.HealthStatus
            Статус       = $d.OperationalStatus
            Размер_ГБ    = [math]::Round($d.Size/1GB, 1)
            Темп_C       = $rc.Temperature
            Износ        = $rc.Wear
            Ошибки_чт    = $rc.ReadErrorsUncorrected
            Ошибки_зап   = $rc.WriteErrorsUncorrected
        }
    }
    $health | Format-Table -AutoSize

    # ---- 2. Обзор дисков ----
    Write-Host "=== ДИСКИ (обзор) ===" -ForegroundColor Green
    Get-Disk | Select-Object Number, FriendlyName, BusType, OperationalStatus,
        @{n='Свободно_ГБ';e={[math]::Round(($_.Size - $_.AllocatedSize)/1GB,1)}} |
        Format-Table -AutoSize

    # ---- 3. Разделы ----
    Write-Host "=== РАЗДЕЛЫ ===" -ForegroundColor Green
    Get-Partition | Select-Object DiskNumber, PartitionNumber, DriveLetter, Type,
        @{n='Размер_ГБ';e={[math]::Round($_.Size/1GB,1)}} |
        Format-Table -AutoSize

    # Отчёт сохраняем рядом со скриптом
    $csv = "$PSScriptRoot\smart_$env:COMPUTERNAME_$stamp.csv"
    $health | Export-Csv $csv -NoTypeInformation -Encoding UTF8
    Write-Host "Отчёт SMART сохранён: $csv" -ForegroundColor Yellow
} else {
    # ---- Упрощённый отчёт (нет прав админа) ----
    Write-Host "=== ДИСКИ (без прав администратора, WMI) ===" -ForegroundColor Green
    Get-CimInstance Win32_DiskDrive | Select-Object Model, InterfaceType,
        @{n='Размер_ГБ';e={[math]::Round($_.Size/1GB,1)}}, Status |
        Format-Table -AutoSize
}

# ---- 4. Тома / место (работает всегда) ----
Write-Host "=== ТОМА (место на дисках) ===" -ForegroundColor Green
Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystem,
    @{n='Размер_ГБ';e={[math]::Round($_.Size/1GB,1)}},
    @{n='Свободно_ГБ';e={[math]::Round($_.SizeRemaining/1GB,1)}},
    @{n='Свободно_%'; e={if ($_.Size) { [math]::Round($_.SizeRemaining/$_.Size*100) }}},
    HealthStatus | Format-Table -AutoSize