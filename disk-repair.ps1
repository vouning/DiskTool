<#
===========================================================================
  ПОЧИНКА ДИСКОВ — работа с «мёртвыми» секторами и поверхностью
===========================================================================
  ТОЛЬКО ОТ АДМИНИСТРАТОРА.

  Важная правда про «лечение» битых секторов:
    * У HDD сбойные сектора программно НЕ восстанавливаются. Контроллер
      диска помечает их и переносит данные в резервную зону (remapping).
      Наша задача — заставить его это сделать: перечитать/перезаписать
      сектора и сообщить о сбойных.
    * У SSD «битых» секторов нет — есть износ ячеек, им управляет
      контроллер сам. Полная проверка для SSD бесполезна и тратит
      ресурс перезаписи.

  Режимы (по скорости: от быстрого к полному):
    -Mode Scan      быстрый фон. скан поверхности (ничего не меняет)  [сек]
    -Mode SpotFix   быстрое исправление проблем, найденных сканом      [сек]
    -Mode Full      полная проверка + remapping (chkdsk /r)           [минуты-часы]
                    Для HDD с уже известными битыми секторами.

  Примеры:
    powershell -ExecutionPolicy Bypass -File disk-repair.ps1 -Drive D -Mode SpotFix
    powershell -ExecutionPolicy Bypass -File disk-repair.ps1 -Drive C -Mode Full
===========================================================================
#>

param(
    [string]$Drive = "C",
    [ValidateSet('Scan','SpotFix','Full')]
    [string]$Mode = 'Scan'
)

$ErrorActionPreference = 'Stop'

# --- Проверка прав ---
$isAdmin = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Ошибка: нужны права администратора! Запустите PowerShell от имени администратора." -ForegroundColor Red
    exit 1
}

# --- Проверка, что том существует ---
if (-not (Get-Volume -DriveLetter $Drive -ErrorAction SilentlyContinue)) {
    Write-Host "Ошибка: тома $Drive не существует." -ForegroundColor Red
    exit 1
}

Write-Host "Диск $Drive — режим: $Mode" -ForegroundColor Cyan
Write-Host ""

switch ($Mode) {
    'Scan' {
        Write-Host "[1/1] Быстрое фоновое сканирование тома $Drive (без изменений)..."
        if (Get-Command Repair-Volume -ErrorAction SilentlyContinue) {
            Repair-Volume -DriveLetter $Drive -Scan
        } else {
            Write-Host "Repair-Volume недоступен (нужна сборка 1709+). Использую chkdsk /scan"
            chkdsk "$Drive`:" /scan
        }
    }
    'SpotFix' {
        Write-Host "[1/1] SpotFix: исправляю найденные проблемы тома $Drive (онлайн)..."
        if (Get-Command Repair-Volume -ErrorAction SilentlyContinue) {
            Repair-Volume -DriveLetter $Drive -SpotFix
        } else {
            Write-Host "Repair-Volume недоступен. Использую chkdsk /f"
            chkdsk "$Drive`:" /f
        }
    }
    'Full' {
        Write-Host "ВНИМАНИЕ: полная проверка может занять от минут до часов." -ForegroundColor Yellow
        Write-Host "Сбойные сектора будут перечитаны, помечены, данные перенесены в резервную зону."
        Write-Host "Для SSD этот режим не нужен — пропустите его."
        $confirm = Read-Host "Продолжить? (y/n)"
        if ($confirm -notmatch '^(y|д|yes|да)$') { Write-Host "Отменено."; exit }

        if ($Drive -eq ($env:SystemDrive -replace ':', '')) {
            Write-Host "Это системный диск — проверка назначится при следующей перезагрузке." -ForegroundColor Cyan
        }
        chkdsk "$Drive`:" /r /x
    }
}

Write-Host ""
Write-Host "Готово." -ForegroundColor Green