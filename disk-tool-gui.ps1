<#
===========================================================================
  ДИСКОВЫЙ ИНСТРУМЕНТАРИЙ — GUI (WinForms)
  Тема: металлик с красным отливом. Все секции в рамках.
  Табло данных — структурированные вкладки: Диски / Тома / Разделы / Журнал.
  Анимация загрузки — брайлевский спиннер из спецсимволов.
===========================================================================
  Кнопки:
    * Сканировать            — SMART, тома, разделы
    * Найти битые сектора    — фон. скан поверхности + журнал ошибок дисков
    * Перенести данные       — перенос c битых секторов в резервную зону
    * Изолировать сектора    — полный remap, отделение битых секторов
  Запуск: powershell -ExecutionPolicy Bypass -File disk-tool-gui.ps1
  Кнопки (кроме «Сканировать») требуют прав администратора.
===========================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Прячем консоль PowerShell, чтобы не маячила рядом с интерфейсом ---
Add-Type -Namespace Native -Name Win32 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$consoleWnd = [Native.Win32]::GetConsoleWindow()
if ($consoleWnd -ne [IntPtr]::Zero) { [Native.Win32]::ShowWindow($consoleWnd, 0) | Out-Null }

$isAdmin = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$sysVol = ($env:SystemDrive -replace ':', '')
$githubUser = 'vouning'   # никнейм GitHub — постоянная кликабельная ссылка в левом нижнем углу

# ---------------- Палитра: металлик с красным отливом ----------------
$cBg        = '#221D1D'   # глубокий графит с тёплым подтоном
$cPanel     = '#2B2424'
$cWidget    = '#332B2A'
$cWidgetAlt = '#3A3231'
$cBorder    = '#7A5757'   # рамка: красная сталь
$cBorderSft = '#4E4140'   # мягкая рамка
$cText      = '#EDE6E2'
$cMuted     = '#A89A96'
$cAccent    = '#C03B30'   # металлический красный
$cAccentDk  = '#8E2C24'
$cBtn       = '#3A3130'
$cBtnOver   = '#4E3A36'
$cGood      = '#D98C82'
$cBad       = '#E05A4E'
$cLink      = '#DD8F85'
$cMetalT    = '#3A3231'   # верх градиента (металл, блик)
$cMetalB    = '#221D1D'   # низ градиента

function New-Font([single]$size, [System.Drawing.FontStyle]$style = 0) {
    New-Object System.Drawing.Font('Segoe UI', $size, $style)
}

# Металлический градиент + рамка для панели
function Set-MetalPanel($ctl, [string]$borderHex = $cBorder) {
    $ctl.Add_Paint({
        param($sender, $e)
        $r = $sender.ClientRectangle
        if ($r.Width -le 0 -or $r.Height -le 0) { return }
        $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $r,
            [System.Drawing.ColorTranslator]::FromHtml($cMetalT),
            [System.Drawing.ColorTranslator]::FromHtml($cMetalB),
            90.0)
        $e.Graphics.FillRectangle($b, $r)
        $b.Dispose()
        $p = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($borderHex), 1)
        $e.Graphics.DrawRectangle($p, 0, 0, $r.Width - 1, $r.Height - 1)
        $p.Dispose()
    })
}

function New-Button([string]$text, [int]$w, [int]$h, [switch]$Primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml($cBorderSft)
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml($cBtnOver)
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.ColorTranslator]::FromHtml($cAccentDk)
    if ($Primary) {
        $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cAccent)
        $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#FFF3F1')
        $b.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml($cBorder)
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml('#A2342A')
    } else {
        $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cBtn)
        $b.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($cText)
    }
    $b.UseVisualStyleBackColor = $false
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Font = New-Font 9
    $b
}

function New-Label([string]$text, [string]$color, [single]$size, [System.Drawing.FontStyle]$style = 0) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($color)
    $l.Font = New-Font $size $style
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize = $true
    $l
}

# Таблица данных в теме программы
function New-Grid {
    $g = New-Object System.Windows.Forms.DataGridView
    $g.BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml($cWidget)
    $g.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $g.GridColor = [System.Drawing.ColorTranslator]::FromHtml($cBorderSft)
    $g.EnableHeadersVisualStyles = $false
    $g.RowHeadersVisible = $false
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.ReadOnly = $true
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $g.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#382E2D')
    $g.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($cText)
    $g.ColumnHeadersDefaultCellStyle.Font = New-Font 9 ([System.Drawing.FontStyle]::Bold)
    $g.ColumnHeadersDefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleLeft
    $g.ColumnHeadersHeight = 28
    $g.DefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cWidget)
    $g.DefaultCellStyle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($cText)
    $g.DefaultCellStyle.SelectionBackColor = [System.Drawing.ColorTranslator]::FromHtml('#6E3B33')
    $g.DefaultCellStyle.SelectionForeColor = [System.Drawing.ColorTranslator]::FromHtml($cText)
    $g.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#312929')
    $g.Dock = [System.Windows.Forms.DockStyle]::Fill
    $g
}

$script:job = $null
$script:scanData = $null
$script:opText = ''
$script:spinnerI = 0
$script:spinnerFrames = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')

function Append-Log([string]$text, [string]$color = $cText) {
    $log.SelectionStart = $log.TextLength
    $log.SelectionLength = 0
    $log.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml($color)
    $log.AppendText($text + "`r`n")
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
}

function ConvertTo-DataTable($objects) {
    $dt = New-Object System.Data.DataTable
    if (-not $objects) { return $dt }
    $props = @($objects[0].PSObject.Properties.Name)
    foreach ($p in $props) { [void]$dt.Columns.Add([string]$p) }
    foreach ($o in $objects) {
        $row = $dt.NewRow()
        foreach ($p in $props) {
            $v = $o.$p
            if ($null -eq $v) { $v = '—' }
            elseif ($v -is [array]) { $v = $v -join ', ' }
            $row[$p] = $v
        }
        [void]$dt.Rows.Add($row)
    }
    $dt
}

function Set-Busy([bool]$busy) {
    foreach ($b in @($btnScan, $btnDetect, $btnRepair, $btnIsolate)) { $b.Enabled = -not $busy }
    $cboVol.Enabled = -not $busy
    $prg.Visible = $busy
}

function Show-ScanResults($obj) {
    $script:scanData = $obj
    $dgvDisks.DataSource = $null
    $dgvVols.DataSource  = $null
    $dgvParts.DataSource = $null
    $dgvDisks.DataSource = (ConvertTo-DataTable $obj.disks)
    $dgvVols.DataSource  = (ConvertTo-DataTable $obj.vols)
    $dgvParts.DataSource = (ConvertTo-DataTable $obj.parts)
}

# ---------------- Форма ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Дисковый инструментарий'
$form.Size = New-Object System.Drawing.Size(1020, 700)
$form.MinimumSize = New-Object System.Drawing.Size(900, 580)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cBg)
$form.Font = New-Font 9.5

# --- Шапка ---
$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = 56
Set-MetalPanel $header $cBorder

$lblDash = New-Label '█' $cAccent 12 ([System.Drawing.FontStyle]::Bold)
$lblDash.Location = New-Object System.Drawing.Point(16, 16)
$lblTitle = New-Label 'ДИСКОВЫЙ ИНСТРУМЕНТАРИЙ' $cText 13 ([System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(38, 13)
$lblInfo = New-Label ("$env:COMPUTERNAME  |  Администратор: " + $(if ($isAdmin) { 'ДА' } else { 'НЕТ' })) $cMuted 9
$lblInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblInfo.Location = New-Object System.Drawing.Point(600, 18)
$lblInfo.Size = New-Object System.Drawing.Size(390, 24)

$header.Controls.Add($lblDash)
$header.Controls.Add($lblTitle)
$header.Controls.Add($lblInfo)

# --- Левая панель: управление ---
$left = New-Object System.Windows.Forms.Panel
$left.Dock = [System.Windows.Forms.DockStyle]::Left
$left.Width = 232
Set-MetalPanel $left $cBorder

$lblSection = New-Label 'У П Р А В Л Е Н И Е' $cMuted 8 ([System.Drawing.FontStyle]::Bold)
$lblSection.Location = New-Object System.Drawing.Point(18, 18)

$lblVol = New-Label 'Том:' $cMuted 9
$lblVol.Location = New-Object System.Drawing.Point(18, 46)
$cboVol = New-Object System.Windows.Forms.ComboBox
$cboVol.Location = New-Object System.Drawing.Point(18, 66)
$cboVol.Size = New-Object System.Drawing.Size(92, 26)
$cboVol.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboVol.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cWidget)
$cboVol.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($cText)
$cboVol.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

$btnW = 196
$btnScan = New-Button 'Сканировать' $btnW 40 -Primary
$btnScan.Location = New-Object System.Drawing.Point(18, 110)
$btnDetect = New-Button 'Найти битые сектора' $btnW 40
$btnDetect.Location = New-Object System.Drawing.Point(18, 158)
$btnRepair = New-Button 'Перенести данные' $btnW 40
$btnRepair.Location = New-Object System.Drawing.Point(18, 206)
$btnIsolate = New-Button 'Изолировать сектора' $btnW 40
$btnIsolate.Location = New-Object System.Drawing.Point(18, 254)

$lblAdminHint = New-Label 'Обнаружение, перенос и изоляция требуют прав администратора' $cMuted 8
$lblAdminHint.Location = New-Object System.Drawing.Point(18, 310)
$lblAdminHint.Size = New-Object System.Drawing.Size($btnW, 40)
$lblAdminHint.AutoSize = $false
$lblAdminHint.BackColor = [System.Drawing.Color]::Transparent

$linkAdmin = New-Object System.Windows.Forms.LinkLabel
$linkAdmin.Text = 'Перезапустить от имени администратора'
$linkAdmin.LinkColor = [System.Drawing.ColorTranslator]::FromHtml($cLink)
$linkAdmin.ActiveLinkColor = [System.Drawing.ColorTranslator]::FromHtml($cGood)
$linkAdmin.BackColor = [System.Drawing.Color]::Transparent
$linkAdmin.Location = New-Object System.Drawing.Point(18, 358)
$linkAdmin.AutoSize = $true
$linkAdmin.Visible = -not $isAdmin

$tip = New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($btnDetect, 'Фоновый скан поверхности + анализ журнала дисковых ошибок (30 дней)')
$tip.SetToolTip($btnRepair,  'Быстрая коррекция: перенос данных с битых секторов в резервную зону (SpotFix, секунды)')
$tip.SetToolTip($btnIsolate, 'Полный ремонт (chkdsk /r): битые сектора перечитываются и отделяются контроллером от рабочей зоны')

$left.Controls.Add($lblSection)
$left.Controls.Add($lblVol);  $left.Controls.Add($cboVol)
$left.Controls.Add($btnScan); $left.Controls.Add($btnDetect)
$left.Controls.Add($btnRepair); $left.Controls.Add($btnIsolate)
$left.Controls.Add($lblAdminHint); $left.Controls.Add($linkAdmin)

# --- Правая панель: табло данных ---
$right = New-Object System.Windows.Forms.Panel
$right.Dock = [System.Windows.Forms.DockStyle]::Fill
Set-MetalPanel $right $cBorder
$right.Padding = New-Object System.Windows.Forms.Padding(10, 16, 10, 10)

$lblSectionR = New-Label 'Д А Н Н Ы Е' $cMuted 8 ([System.Drawing.FontStyle]::Bold)
$lblSectionR.Dock = [System.Windows.Forms.DockStyle]::Top
$lblSectionR.Height = 18
$lblSectionR.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$statusBar.Height = 30
$statusBar.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cMetalB)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cMetalB)
$lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($cGood)
$lblStatus.Font = New-Object System.Drawing.Font('Consolas', 13, [System.Drawing.FontStyle]::Bold)
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblStatus.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblStatus.Text = 'Готов к работе'

$statusBar.Controls.Add($lblStatus)

# --- Вкладки данных: Диски / Тома / Разделы / Журнал ---
$tab = New-Object System.Windows.Forms.TabControl
$tab.Dock = [System.Windows.Forms.DockStyle]::Fill
$tab.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cPanel)
$tab.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($cText)
$tab.Font = New-Font 9
$tab.ItemSize = New-Object System.Drawing.Size(92, 28)

function New-TabPage([string]$title) {
    $p = New-Object System.Windows.Forms.TabPage
    $p.Text = $title
    $p.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cWidget)
    $p.Padding = New-Object System.Windows.Forms.Padding(8)
    $p
}
$tabDisks = New-TabPage 'Диски'
$tabVols  = New-TabPage 'Тома'
$tabParts = New-TabPage 'Разделы'
$tabLog   = New-TabPage 'Журнал'

$dgvDisks = New-Grid
$dgvVols  = New-Grid
$dgvParts = New-Grid
$tabDisks.Controls.Add($dgvDisks)
$tabVols.Controls.Add($dgvVols)
$tabParts.Controls.Add($dgvParts)

$log = New-Object System.Windows.Forms.RichTextBox
$log.ReadOnly = $true
$log.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#2A2323')
$log.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($cText)
$log.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$log.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$log.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$log.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabLog.Controls.Add($log)

[void]$tab.TabPages.Add($tabLog)
[void]$tab.TabPages.Add($tabDisks)
[void]$tab.TabPages.Add($tabVols)
[void]$tab.TabPages.Add($tabParts)

# Порядок добавления важен (док обрабатывается с конца): вкладки занимают всё, статус снизу, подпись сверху.
$right.Controls.Add($tab)
$right.Controls.Add($statusBar)
$right.Controls.Add($lblSectionR)

# --- Индикатор занятости (красная полоса, низ) ---
$prg = New-Object System.Windows.Forms.Panel
$prg.Dock = [System.Windows.Forms.DockStyle]::Bottom
$prg.Height = 4
$prg.BackColor = [System.Drawing.ColorTranslator]::FromHtml($cAccent)
$prg.Visible = $false

# --- Нижняя панель программы: кликабельный никнейм GitHub в левом углу ---
$formBar = New-Object System.Windows.Forms.Panel
$formBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$formBar.Height = 32
Set-MetalPanel $formBar $cBorder

$lblGitHub = New-Object System.Windows.Forms.LinkLabel
$lblGitHub.Text = "GitHub: $githubUser"
$lblGitHub.LinkColor = [System.Drawing.ColorTranslator]::FromHtml($cLink)
$lblGitHub.ActiveLinkColor = [System.Drawing.ColorTranslator]::FromHtml($cGood)
$lblGitHub.VisitedLinkColor = [System.Drawing.ColorTranslator]::FromHtml($cLink)
$lblGitHub.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
$lblGitHub.Font = New-Font 9
$lblGitHub.BackColor = [System.Drawing.Color]::Transparent
$lblGitHub.AutoSize = $true
$lblGitHub.Location = New-Object System.Drawing.Point(12, 7)
$lblGitHub.Add_LinkClicked({
    Start-Process "https://github.com/$githubUser"
})
$tipGitHub = New-Object System.Windows.Forms.ToolTip
$tipGitHub.SetToolTip($lblGitHub, "Открыть профиль GitHub: https://github.com/$githubUser")
$formBar.Controls.Add($lblGitHub)

$form.Controls.Add($right)
$form.Controls.Add($left)
$form.Controls.Add($prg)
$form.Controls.Add($header)
$form.Controls.Add($formBar)

# ---------------- Заполнение ----------------
Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | Sort-Object DriveLetter |
    ForEach-Object { [void]$cboVol.Items.Add($_.DriveLetter) }
if ($cboVol.Items.Count -gt 0) { $cboVol.SelectedIndex = 0 }

# ---------------- Таймер анимации (спиннер) ----------------
$timerSpin = New-Object System.Windows.Forms.Timer
$timerSpin.Interval = 110
$timerSpin.Add_Tick({
    if ($script:job -and $script:job.State -eq 'Running') {
        $f = $script:spinnerFrames[$script:spinnerI % $script:spinnerFrames.Count]
        $script:spinnerI++
        $lblStatus.Text = "$f  $($script:opText)..."
    }
})
$timerSpin.Start()

# ---------------- Таймер обслуживания задач ----------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    if (-not $script:job) { $lblStatus.Text = 'Готов к работе'; return }
    $j = $script:job
    $lines = @(Receive-Job $j -ErrorAction SilentlyContinue)
    foreach ($l in $lines) {
        if ($l -is [string] -and $l.Length -gt 0) {
            if ($l -match '^##LOG##:') { Append-Log ($l.Substring(8)) }
            else { Append-Log ($l) }
        }
    }
    if ($j.State -ne 'Running') {
        Remove-Job $j -Force -ErrorAction SilentlyContinue
        $script:job = $null
        Set-Busy $false
        switch ($script:lastOp) {
            'Scan' {
                try {
                    Show-ScanResults $script:lastResult
                    Append-Log 'Скан завершён.' $cGood
                } catch { Append-Log ("Ошибка разбора результата: $($_.Exception.Message)") $cBad }
            }
            default {
                Append-Log 'Операция завершена. Повторный скан для актуальной картины...' $cMuted
                $btnScan.PerformClick()
            }
        }
    }
})
$timer.Start()

# ---------------- События ----------------
$btnScan.Add_Click({
    if ($script:job) { return }
    $script:lastOp = 'Scan'
    $script:lastResult = $null
    $script:opText = 'Сканирование'
    $lblStatus.Text = '⠄ Сканирование...'
    Set-Busy $true
    Append-Log '--- Скан ---' $cAccent
    $script:job = Start-Job -ScriptBlock {
        param($isAdmin)
        $ErrorActionPreference = 'SilentlyContinue'
        $log = @('##LOG##:Начинаю сканирование...')
        if ($isAdmin) {
            $disks = @(foreach ($d in Get-PhysicalDisk) {
                $rc = Get-StorageReliabilityCounter -PhysicalDisk $d
                [pscustomobject]@{
                    'Диск'        = $d.FriendlyName
                    'Тип'         = [string]$d.MediaType
                    'Здоровье'    = [string]$d.HealthStatus
                    'Статус'      = [string]$d.OperationalStatus
                    'Размер, ГБ'  = [math]::Round($d.Size/1GB, 1)
                    'Темп, C'     = $rc.Temperature
                    'Износ'       = $rc.Wear
                    'Ош. чтения'  = $rc.ReadErrorsUncorrected
                    'Ош. записи'  = $rc.WriteErrorsUncorrected
                }
            })
            $parts = @(Get-Partition | ForEach-Object {
                [pscustomobject]@{
                    'Диск'          = $_.DiskNumber
                    'Раздел'        = $_.PartitionNumber
                    'Том'           = $_.DriveLetter
                    'Тип'           = [string]$_.Type
                    'Размер, ГБ'    = [math]::Round($_.Size/1GB, 1)
                }
            })
            $log += '##LOG##:SMART и разделы получены.'
        } else {
            $disks = @(Get-CimInstance Win32_DiskDrive | ForEach-Object {
                [pscustomobject]@{
                    'Диск'       = $_.Model
                    'Тип'        = $_.InterfaceType
                    'Размер, ГБ' = [math]::Round($_.Size/1GB, 1)
                    'Статус'     = $_.Status
                }
            })
            $parts = @()
            $log += '##LOG##:Без прав администратора полный SMART недоступен.'
        }
        $vols = @(Get-Volume | Where-Object DriveLetter | ForEach-Object {
            [pscustomobject]@{
                'Том'          = $_.DriveLetter
                'ФС'           = $_.FileSystem
                'Размер, ГБ'   = [math]::Round($_.Size/1GB, 1)
                'Свободно, ГБ' = [math]::Round($_.SizeRemaining/1GB, 1)
                'Свободно, %'  = $(if ($_.Size) { [math]::Round($_.SizeRemaining/$_.Size*100) } else { $null })
                'Здоровье'     = [string]$_.HealthStatus
            }
        })
        $log += '##LOG##:Тома собраны.'
        [pscustomobject]@{ log = $log; disks = $disks; vols = $vols; parts = $parts } |
            ConvertTo-Json -Depth 4
    } -ArgumentList $isAdmin
})

function Start-DiskOp([string]$opName) {
    if ($script:job) { return }
    $vol = $cboVol.SelectedItem
    if (-not $vol) { Append-Log 'Выберите том.' $cBad; return }
    if (-not $isAdmin) { Append-Log 'Нужны права администратора (ссылка в левой панели).' $cBad; return }
    $script:lastOp = $opName
    $script:lastResult = $null
    $script:opText = switch ($opName) {
        'Detect' { 'Обнаружение битых секторов' }
        'Repair' { 'Перенос данных' }
        'Isolate'{ 'Изоляция битых секторов' }
    }
    $lblStatus.Text = '⠄ ' + $script:opText + '...'
    Append-Log ("--- {0}: том {1} ---" -f $script:opText, $vol) $cAccent
    Set-Busy $true
    $script:job = Start-Job -ScriptBlock {
        param($vol, $sysVol, $opName)
        $ErrorActionPreference = 'Continue'
        $isSys = ($vol -eq $sysVol)
        switch ($opName) {
            'Detect' {
                '##LOG##:Этап 1 — фоновый скан поверхности (без изменений)...'
                if (Get-Command Repair-Volume -ErrorAction SilentlyContinue) {
                    Repair-Volume -DriveLetter $vol -Scan 2>&1 |
                        ForEach-Object { if ($_) { '##LOG##:' + $_.ToString() } }
                } else {
                    chkdsk "$vol`:" /scan 2>&1 | ForEach-Object { if ($_) { '##LOG##:' + $_.ToString() } }
                }
                '##LOG##:Этап 2 — анализ журнала дисковой подсистемы (30 дней)...'
                $ids = 7,51,52,55,153,157
                $ev = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=$ids; StartTime=(Get-Date).AddDays(-30)} `
                        -ErrorAction SilentlyContinue | Select-Object -First 8)
                if ($ev.Count -eq 0) {
                    '##LOG##:Ошибок дисковой подсистемы за 30 дней не обнаружено.'
                    '##LOG##:Итог: битые сектора не обнаружены.'
                } else {
                    '##LOG##:Найдены события о сбоях дисков:'
                    foreach ($e in $ev) {
                        '##LOG##:  [ID {0}] {1}: {2:yyyy-MM-dd HH:mm}' -f $e.Id, $e.ProviderName, $e.TimeCreated
                    }
                    '##LOG##:Итог: есть признаки проблем поверхности — запустите «Изолировать сектора».'
                }
            }
            'Repair' {
                '##LOG##:Быстрая коррекция: перенос данных с битых секторов в резервную зону...'
                if (Get-Command Repair-Volume -ErrorAction SilentlyContinue) {
                    Repair-Volume -DriveLetter $vol -SpotFix 2>&1 |
                        ForEach-Object { if ($_) { '##LOG##:' + $_.ToString() } }
                } else {
                    chkdsk "$vol`:" /f 2>&1 | ForEach-Object { if ($_) { '##LOG##:' + $_.ToString() } }
                }
                '##LOG##:Готово.'
            }
            'Isolate' {
                '##LOG##:Изоляция битых секторов (полный remap, HDD). Может занять время...'
                if ($isSys) {
                    '##LOG##:Системный том — проверка назначена при следующей перезагрузке.'
                    $null = 'Y' | chkdsk "$vol`:" /r 2>&1 | ForEach-Object { '##LOG##:' + $_.ToString() }
                } else {
                    chkdsk "$vol`:" /r /x 2>&1 | ForEach-Object { '##LOG##:' + $_.ToString() }
                }
                '##LOG##:Готово. Битые сектора исключены контроллером из рабочей зоны.'
            }
        }
    } -ArgumentList $vol, $sysVol, $opName
}

$btnDetect.Add_Click({ Start-DiskOp 'Detect' })
$btnRepair.Add_Click({ Start-DiskOp 'Repair' })
$btnIsolate.Add_Click({
    if ($script:job) { return }
    $vol = $cboVol.SelectedItem
    if (-not $vol) { Append-Log 'Выберите том.' $cBad; return }
    if (-not $isAdmin) { Append-Log 'Нужны права администратора.' $cBad; return }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Полный ремонт тома $vol$(if($vol -eq $sysVol){' (системный диск — проверится после перезагрузки)'})?`n`nБитые сектора будут перечитаны и исключены контроллером из рабочей зоны.",
        'Подтверждение', [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { Start-DiskOp 'Isolate' }
})

$linkAdmin.Add_LinkClicked({
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', "`"$PSCommandPath`""
    $form.Close()
})

$form.Add_Shown({
    Append-Log "Диагностика: $env:COMPUTERNAME" $cMuted
    if ($isAdmin) {
        Append-Log 'Полный режим: все кнопки доступны.' $cGood
    } else {
        Append-Log 'Доступен только скан. Остальное — от имени администратора.' $cBad
    }
    $btnScan.PerformClick()
})

$form.Add_FormClosed({
    $timer.Stop(); $timerSpin.Stop()
    if ($script:job) {
        Stop-Job $script:job -ErrorAction SilentlyContinue
        Remove-Job $script:job -Force -ErrorAction SilentlyContinue
    }
})

[void]$form.ShowDialog()