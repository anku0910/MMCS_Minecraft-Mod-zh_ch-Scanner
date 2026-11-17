#requires -Version 5.1
<#
.SYNOPSIS
    zh_cn / 語言檔掃描工具（背景掃描、可取消、支援萬用字元、排除資料夾、排序、匯出 CSV、記憶設定）。
    遞迴掃描指定路徑下符合「檔名比對」的檔案/資料夾；比對值以 zh_cn 開頭時，
    同一資料夾若有對應 zh_tw 也一併顯示。
    檔名比對支援萬用字元（* ?）；不含萬用字元＝精確比對主檔名、忽略副檔名。
    路徑可直接輸入、貼上、拖曳，按 Enter 掃描。
    雙擊清單列＝開啟所在資料夾；支援複製路徑清單、匯出 CSV、開啟檔案。
#>
param([string]$InitialPath = "")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------- 設定載入 ----------
$script:settingsPath = Join-Path $PSScriptRoot 'MMCS.settings.json'
$settings = @{
    Path     = ''
    Pattern  = '*zh_cn*'
    Excludes = '.git, node_modules'
    Left     = ''
    Top      = ''
    Width    = '920'
    Height   = '660'
    Maximized = $false
}
if (Test-Path $script:settingsPath) {
    try {
        $loaded = Get-Content $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in @('Path','Pattern','Excludes','Left','Top','Width','Height')) {
            if ($loaded.PSObject.Properties[$key] -and $null -ne $loaded.$key -and "$($loaded.$key)" -ne '') { $settings[$key] = "$($loaded.$key)" }
        }
        if ($loaded.PSObject.Properties['Maximized']) { $settings['Maximized'] = [bool]$loaded.Maximized }
    } catch { }
}

$script:results = [System.Collections.Generic.List[PSObject]]::new()
$script:resultsData = @()
$script:scanning = $false
$script:scanSync = $null
$script:scanPS = $null
$script:scanRunspace = $null
$script:scanStart = $null
$script:sortField = $null
$script:sortDesc = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = "MMCS - Minecraft Mod zh_cn Scanner"
$form.Size = New-Object System.Drawing.Size([int]$settings.Width, [int]$settings.Height)
$form.StartPosition = "Manual"
if ("$($settings.Left)" -ne '' -and "$($settings.Top)" -ne '') {
    $form.Location = New-Object System.Drawing.Point([int]$settings.Left, [int]$settings.Top)
} else {
    $form.StartPosition = "CenterScreen"
}
$form.MinimumSize = New-Object System.Drawing.Size(740, 620)
$form.AllowDrop = $true
if ($settings.Maximized) { $form.WindowState = 'Maximized' }

# ---------- 頂部輸入區（Dock=Top） ----------
$pnlTop = New-Object System.Windows.Forms.Panel
$pnlTop.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlTop.Height = 118
$pnlTop.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Location = New-Object System.Drawing.Point(8, 10)
$lblPath.Size = New-Object System.Drawing.Size(640, 20)
$lblPath.Text = "掃描路徑（可直接輸入、貼上，或把資料夾拖進來，按 Enter 掃描）："

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(8, 32)
$txtPath.Size = New-Object System.Drawing.Size(600, 23)
$txtPath.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtPath.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::SuggestAppend
$txtPath.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::FileSystemDirectories
if ("$($settings.Path)" -ne '') { $txtPath.Text = $settings.Path }
if ($InitialPath) { $txtPath.Text = $InitialPath }

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "開始掃描"
$btnScan.Location = New-Object System.Drawing.Point(616, 29)
$btnScan.Size = New-Object System.Drawing.Size(110, 27)
$btnScan.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$lblPattern = New-Object System.Windows.Forms.Label
$lblPattern.Location = New-Object System.Drawing.Point(8, 64)
$lblPattern.Size = New-Object System.Drawing.Size(900, 20)
$lblPattern.Text = "檔名比對（可含 * ? 萬用字元，例：zh_cn.*＝zh_cn 加任意副檔名；無萬用字元＝精確比對主檔名；zh_cn 開頭自動配對 zh_tw）："

$txtPattern = New-Object System.Windows.Forms.TextBox
$txtPattern.Location = New-Object System.Drawing.Point(8, 86)
$txtPattern.Size = New-Object System.Drawing.Size(320, 23)
$txtPattern.Text = $settings.Pattern

$lblExcl = New-Object System.Windows.Forms.Label
$lblExcl.Location = New-Object System.Drawing.Point(344, 89)
$lblExcl.Size = New-Object System.Drawing.Size(170, 20)
$lblExcl.Text = "排除資料夾（逗號分隔）："

$txtExcl = New-Object System.Windows.Forms.TextBox
$txtExcl.Location = New-Object System.Drawing.Point(520, 86)
$txtExcl.Size = New-Object System.Drawing.Size(270, 23)
$txtExcl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtExcl.Text = $settings.Excludes

$pnlTop.Controls.AddRange(@($lblPath, $txtPath, $btnScan, $lblPattern, $txtPattern, $lblExcl, $txtExcl))

# ---------- 結果清單（Dock=Fill，隨視窗縮放） ----------
$lv = New-Object System.Windows.Forms.ListView
$lv.View = "Details"
$lv.FullRowSelect = $true
$lv.GridLines = $true
$lv.Dock = [System.Windows.Forms.DockStyle]::Fill

$colNo = New-Object System.Windows.Forms.ColumnHeader
$colNo.Text = "No."
$colNo.Width = 50
$colType = New-Object System.Windows.Forms.ColumnHeader
$colType.Text = "類型"
$colType.Width = 80
$colLang = New-Object System.Windows.Forms.ColumnHeader
$colLang.Text = "主檔名"
$colLang.Width = 110
$colSize = New-Object System.Windows.Forms.ColumnHeader
$colSize.Text = "大小"
$colSize.Width = 80
$colTime = New-Object System.Windows.Forms.ColumnHeader
$colTime.Text = "修改日期"
$colTime.Width = 125
$colPath = New-Object System.Windows.Forms.ColumnHeader
$colPath.Text = "完整路徑"
$colPath.Width = 445
$lv.Columns.AddRange(@($colNo, $colType, $colLang, $colSize, $colTime, $colPath))

# ---------- 底部狀態區（Dock=Bottom，永遠貼在最下方） ----------
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlBottom.Height = 90
$pnlBottom.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)

$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Location = New-Object System.Drawing.Point(8, 10)
$lblCount.Size = New-Object System.Drawing.Size(300, 60)
$lblCount.AutoSize = $false
$lblCount.AutoEllipsis = $true
$lblCount.Text = "共 0 個項目"

$btnTreemap = New-Object System.Windows.Forms.Button
$btnTreemap.Text = "樹狀圖"
$btnTreemap.Location = New-Object System.Drawing.Point(330, 6)
$btnTreemap.Size = New-Object System.Drawing.Size(100, 28)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "複製路徑"
$btnCopy.Location = New-Object System.Drawing.Point(440, 6)
$btnCopy.Size = New-Object System.Drawing.Size(100, 28)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "匯出 CSV"
$btnExport.Location = New-Object System.Drawing.Point(550, 6)
$btnExport.Size = New-Object System.Drawing.Size(100, 28)

$btnOpenFile = New-Object System.Windows.Forms.Button
$btnOpenFile.Text = "開啟檔案"
$btnOpenFile.Location = New-Object System.Drawing.Point(660, 6)
$btnOpenFile.Size = New-Object System.Drawing.Size(100, 28)

$btnOpenContaining = New-Object System.Windows.Forms.Button
$btnOpenContaining.Text = "開所在資料夾"
$btnOpenContaining.Location = New-Object System.Drawing.Point(770, 6)
$btnOpenContaining.Size = New-Object System.Drawing.Size(120, 28)

$pnlBottom.Controls.AddRange(@($lblCount, $btnTreemap, $btnCopy, $btnExport, $btnOpenFile, $btnOpenContaining))

# ---------- 加入表單（Dock 順序：Fill 先佔滿，Top/Bottom 再從邊緣切出） ----------
$form.Controls.AddRange(@($lv, $pnlTop, $pnlBottom))
# ---------- 背景掃描（Runspace） ----------
$workerScript = @'
param($Root, $Pattern, $Pair, $Excludes, $Sync)

function Test-Match([string]$Name, [string]$Base, [string]$Pat) {
    if ($Pat -match '[*?]') { return (($Name -like $Pat) -or ($Base -like $Pat)) }
    return ($Base -eq $Pat)
}

$excludeSet = @{}
foreach ($e in ($Excludes -split '[,;]')) {
    $e = $e.Trim()
    if ($e) { $excludeSet[$e.ToLowerInvariant()] = $true }
}

try {
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        if ($Sync.Cancel) { break }
        $dir = $stack.Pop()
        $Sync.Scanned++
        try {
            foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($dir)) {
                $name = [System.IO.Path]::GetFileName($entry)
                try { $attr = [System.IO.File]::GetAttributes($entry) } catch { continue }
                $isDir = ($attr -band [System.IO.FileAttributes]::Directory) -ne 0
                $base = if ($isDir) { $name } else { [System.IO.Path]::GetFileNameWithoutExtension($entry) }
                $isPrimary = Test-Match $name $base $Pattern
                $isPair = $false
                if ($Pair -and -not $isPrimary) { $isPair = Test-Match $name $base $Pair }
                if ($isPrimary -or $isPair) {
                    $size = $null
                    $mtime = $null
                    if ($isDir) {
                        try { $mtime = [System.IO.Directory]::GetLastWriteTime($entry) } catch { }
                    } else {
                        try { $fi = New-Object System.IO.FileInfo($entry); $size = $fi.Length; $mtime = $fi.LastWriteTime } catch { }
                    }
                    $fileType = if ($isDir) { '資料夾' } else { [System.IO.Path]::GetExtension($entry).ToLowerInvariant() }
                    if ($fileType -eq '') { $fileType = '無副檔名' }
                    $Sync.Results.Add([PSCustomObject]@{
                        BaseName = $base
                        Primary  = $isPrimary
                        Type     = $fileType
                        Path     = $entry
                        Parent   = $dir
                        Length   = $size
                        MTime    = $mtime
                    })
                }
                if ($isDir) {
                    if (-not $excludeSet.ContainsKey($name.ToLowerInvariant()) -and
                        -not ($attr -band [System.IO.FileAttributes]::ReparsePoint)) {
                        $stack.Push($entry)
                    }
                }
            }
        } catch { }
    }
    $Sync.Done = $true
} catch {
    $Sync.Error = $_.Exception.Message
    $Sync.Done = $true
}
'@

function Cleanup-Scan {
    if ($script:scanPS) {
        try { $script:scanPS.Stop() } catch { }
        try { $script:scanPS.Dispose() } catch { }
        $script:scanPS = $null
    }
    if ($script:scanRunspace) {
        try { $script:scanRunspace.Dispose() } catch { }
        $script:scanRunspace = $null
    }
    $script:scanSync = $null
}

function Format-Size([double]$L) {
    if ($L -ge 1MB) { return ('{0:N1} MB' -f ($L / 1MB)) }
    if ($L -ge 1KB) { return ('{0:N1} KB' -f ($L / 1KB)) }
    return ("$L B")
}

function Show-Results {
    $lv.BeginUpdate()
    try {
        $lv.Items.Clear()
        $i = 0
        foreach ($item in $script:resultsData) {
            $i++
            $item.No = $i
            $sizeStr = if ($null -ne $item.Length) { Format-Size $item.Length } else { '' }
            $timeStr = if ($item.MTime) { $item.MTime.ToString('yyyy/MM/dd HH:mm') } else { '' }
            $lvi = New-Object System.Windows.Forms.ListViewItem("$i")
            [void]$lvi.SubItems.Add($item.Type)
            [void]$lvi.SubItems.Add($item.BaseName)
            [void]$lvi.SubItems.Add($sizeStr)
            [void]$lvi.SubItems.Add($timeStr)
            [void]$lvi.SubItems.Add($item.Path)
            [void]$lv.Items.Add($lvi)
        }
    }
    finally {
        $lv.EndUpdate()
    }
}

function Finish-Scan {
    $script:scanTimer.Stop()
    $sync = $script:scanSync
    Cleanup-Scan
    $script:scanning = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $btnScan.Text = "開始掃描"
    if (-not $sync) { return }
    if ($sync.Error) {
        [System.Windows.Forms.MessageBox]::Show($form, "掃描失敗：$($sync.Error)", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        $lblCount.Text = "掃描失敗"
        return
    }
    $elapsed = [math]::Round(((Get-Date) - $script:scanStart).TotalSeconds, 1)

    $all = @($sync.Results)
    $primaryParents = @($all | Where-Object { $_.Primary } | Select-Object -ExpandProperty Parent -Unique)
    $display = @($all | Where-Object { $_.Primary -or ($primaryParents -contains $_.Parent) } |
        Sort-Object Parent, BaseName, Path)

    $script:resultsData = @($display | ForEach-Object {
        [PSCustomObject]@{
            No       = 0
            BaseName = $_.BaseName
            Primary  = $_.Primary
            Type     = $_.Type
            Path     = $_.Path
            Parent   = $_.Parent
            Length   = $_.Length
            MTime    = $_.MTime
        }
    })
    $script:sortField = $null
    $script:sortDesc = $false
    Show-Results

    $nPrimary = @($display | Where-Object { $_.Primary }).Count
    $nPair = $display.Count - $nPrimary
    $nLoc = @($display | Select-Object -ExpandProperty Parent -Unique).Count
    $prefix = if ($sync.Cancel) { "已取消，僅顯示部分結果。 " } else { "" }
    if ($display.Count -eq 0) {
        $lblCount.Text = "${prefix}找不到符合的檔案或資料夾（耗時 $elapsed 秒）"
    }
    elseif ($sync.Pair) {
        $lblCount.Text = "${prefix}符合「$($sync.Pattern)」共 $nPrimary 個（另有 $nPair 個 zh_tw 配對），分布於 $nLoc 個位置（耗時 $elapsed 秒）"
    }
    else {
        $lblCount.Text = "${prefix}符合「$($sync.Pattern)」共 $nPrimary 個，分布於 $nLoc 個位置（耗時 $elapsed 秒）"
    }
}

$script:scanTimer = New-Object System.Windows.Forms.Timer
$script:scanTimer.Interval = 250
$script:scanTimer.Add_Tick({
    $sync = $script:scanSync
    if (-not $sync) { $script:scanTimer.Stop(); return }
    if ($sync.Done) { Finish-Scan }
    else { $lblCount.Text = "掃描中… 已掃 $($sync.Scanned) 個資料夾" }
})

function Start-Scan {
    if ($script:scanning) {
        if ($script:scanSync) { $script:scanSync.Cancel = $true }
        return
    }
    $root = $txtPath.Text.Trim()
    if (-not $root) {
        [System.Windows.Forms.MessageBox]::Show($form, "請先輸入一個路徑。", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if (-not (Test-Path $root)) {
        [System.Windows.Forms.MessageBox]::Show($form, "路徑不存在，請確認後再試。", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    try {
        if (-not (Get-Item $root -Force).PSIsContainer) {
            [System.Windows.Forms.MessageBox]::Show($form, "請輸入資料夾路徑，而不是檔案。", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
    } catch { }

    $pattern = $txtPattern.Text.Trim()
    if (-not $pattern) { $pattern = 'zh_cn' }
    $pair = $null
    if ($pattern.ToLowerInvariant().Contains('zh_cn')) {
        $pair = $pattern.ToLowerInvariant().Replace('cn', 'tw')
    }
    $excludes = $txtExcl.Text

    $lv.Items.Clear()
    $script:resultsData = @()
    $script:sortField = $null
    $script:sortDesc = $false
    $lblCount.Text = "掃描中…"
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $btnScan.Text = "停止掃描"
    $script:scanning = $true
    $script:scanStart = Get-Date

    $sync = [hashtable]::Synchronized(@{
        Cancel  = $false
        Done    = $false
        Error   = $null
        Scanned = 0
        Pattern = $pattern
        Pair    = $pair
        Results = [System.Collections.Generic.List[object]]::new()
    })
    $script:scanSync = $sync

    $rs = [runspacefactory]::CreateRunspace()
    $script:scanRunspace = $rs
    $rs.Open()
    $ps = [powershell]::Create()
    $script:scanPS = $ps
    $ps.Runspace = $rs
    [void]$ps.AddScript($workerScript).AddArgument($root).AddArgument($pattern).AddArgument($pair).AddArgument($excludes).AddArgument($sync)
    [void]$ps.BeginInvoke()

    $script:scanTimer.Start()
}

# ---------- 樹狀圖（WizTree 風格輕量版：面積＝檔案大小，顏色＝語系） ----------
$script:tmFont = New-Object System.Drawing.Font('Microsoft JhengHei', 8.25)
$script:tmFontSmall = New-Object System.Drawing.Font('Microsoft JhengHei', 7.5)
$script:tmBrushCn = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38,139,166))
$script:tmBrushTw = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(224,138,43))
$script:tmBrushOther = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110,116,128))
$script:tmBrushFolder = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(52,54,64))
$script:tmBrushText = [System.Drawing.Brushes]::White
$script:tmBrushDim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(185,187,196))

function TM-Worst([double]$Sum, [double]$Mn, [double]$Mx, [double]$Side) {
    $s2 = $Sum * $Sum
    $w2 = $Side * $Side
    return [Math]::Max(($w2 * $Mx) / $s2, $s2 / ($w2 * $Mn))
}

# Squarified treemap：輸入按 Value 由大到小排序的項目，輸出矩形清單
function TM-Squarify {
    param($Items, [double]$X, [double]$Y, [double]$W, [double]$H)
    $out = New-Object System.Collections.Generic.List[object]
    $valid = @($Items | Where-Object { $_.Value -gt 0 })
    if ($valid.Count -eq 0 -or $W -lt 1 -or $H -lt 1) { return $out }
    $total = 0.0
    foreach ($it in $valid) { $total += $it.Value }
    if ($total -le 0) { return $out }
    $scale = ($W * $H) / $total
    $areas = New-Object 'double[]' $valid.Count
    for ($k = 0; $k -lt $valid.Count; $k++) { $areas[$k] = $valid[$k].Value * $scale }
    $i = 0; $cx = $X; $cy = $Y; $cw = $W; $ch = $H
    while ($i -lt $valid.Count -and $cw -gt 0.5 -and $ch -gt 0.5) {
        $side = [Math]::Min($cw, $ch)
        $sum = 0.0; $mn = [double]::MaxValue; $mx = 0.0; $cnt = 0
        while ($i + $cnt -lt $valid.Count) {
            $a = $areas[$i + $cnt]
            if ($cnt -gt 0) {
                $cur = TM-Worst $sum $mn $mx $side
                $ns = $sum + $a
                $nxt = TM-Worst $ns ([Math]::Min($mn, $a)) ([Math]::Max($mx, $a)) $side
                if ($nxt -gt $cur) { break }
            }
            $sum += $a
            if ($a -lt $mn) { $mn = $a }
            if ($a -gt $mx) { $mx = $a }
            $cnt++
        }
        if ($cnt -eq 0) { break }
        if ($cw -ge $ch) {
            $rw = $sum / $ch
            $ry = $cy
            for ($k = 0; $k -lt $cnt; $k++) {
                $rh = $areas[$i + $k] / $rw
                $null = $out.Add([PSCustomObject]@{ X = $cx; Y = $ry; W = $rw; H = $rh; Item = $valid[$i + $k] })
                $ry += $rh
            }
            $cx += $rw; $cw -= $rw
        }
        else {
            $rh = $sum / $cw
            $rx = $cx
            for ($k = 0; $k -lt $cnt; $k++) {
                $rw2 = $areas[$i + $k] / $rh
                $null = $out.Add([PSCustomObject]@{ X = $rx; Y = $cy; W = $rw2; H = $rh; Item = $valid[$i + $k] })
                $rx += $rw2
            }
            $cy += $rh; $ch -= $rh
        }
        $i += $cnt
    }
    return $out
}

# 依 Parent 分組：每個資料夾一個容器，內含其檔案
function TM-Model {
    $files = @($script:resultsData | Where-Object { $null -ne $_.Length -and $_.Length -gt 0 })
    if ($files.Count -eq 0) { return $null }
    $files = @($files | Sort-Object Length -Descending)
    if ($files.Count -gt 2000) {
        $rest = @($files | Select-Object -Skip 2000)
        $restSum = ($rest | Measure-Object -Property Length -Sum).Sum
        $kept = @($files | Select-Object -First 2000)
        $kept += [PSCustomObject]@{ BaseName = "其他 $($rest.Count) 個"; Type = '檔案'; Path = ''; Parent = ''; Length = $restSum; MTime = $null; Primary = $false }
        $files = $kept
    }
    $groups = [ordered]@{}
    foreach ($f in $files) {
        $p = if ($f.Parent) { $f.Parent } else { '(根目錄)' }
        if (-not $groups.Contains($p)) { $groups[$p] = New-Object System.Collections.Generic.List[object] }
        $null = $groups[$p].Add($f)
    }
    $folders = @($groups.GetEnumerator() | ForEach-Object {
        $sum = 0.0
        foreach ($x in $_.Value) { $sum += $x.Length }
        [PSCustomObject]@{ Name = $_.Key; Files = $_.Value; Total = $sum }
    } | Sort-Object Total -Descending)
    return $folders
}

function TM-Draw([System.Drawing.Graphics]$g, [double]$W, [double]$H) {
    $g.Clear([System.Drawing.Color]::FromArgb(24,26,32))
    $script:tmHit.Clear()
    $g.FillRectangle($script:tmBrushCn, 6, 6, 10, 10)
    $g.DrawString("zh_cn", $script:tmFont, $script:tmBrushText, 20, 3)
    $g.FillRectangle($script:tmBrushTw, 90, 6, 10, 10)
    $g.DrawString("zh_tw", $script:tmFont, $script:tmBrushText, 104, 3)
    $g.FillRectangle($script:tmBrushOther, 174, 6, 10, 10)
    $g.DrawString("其他", $script:tmFont, $script:tmBrushText, 188, 3)
    $folders = TM-Model
    if (-not $folders) {
        $g.DrawString("沒有可顯示的檔案（結果為空或皆為資料夾）", $script:tmFont, $script:tmBrushDim, 6, 26)
        return
    }
    $ax = 6.0; $ay = 24.0; $aw = $W - 12.0; $ah = $H - 30.0
    if ($aw -lt 10 -or $ah -lt 10) { return }
    $top = @($folders | ForEach-Object { [PSCustomObject]@{ Value = [double]$_.Total; Ref = $_ } })
    $topRects = @(TM-Squarify $top $ax $ay $aw $ah)
    foreach ($tr in $topRects) {
        $f = $tr.Item.Ref
        $g.FillRectangle($script:tmBrushFolder, [System.Drawing.RectangleF]::new($tr.X, $tr.Y, $tr.W, $tr.H))
        if ($tr.H -gt 14 -and $tr.W -gt 30) {
            $lf = [System.Drawing.RectangleF]::new($tr.X + 3, $tr.Y + 1, $tr.W - 6, 13)
            $g.DrawString($f.Name, $script:tmFontSmall, $script:tmBrushDim, $lf)
        }
        $null = $script:tmHit.Add([PSCustomObject]@{ X = $tr.X; Y = $tr.Y; W = $tr.W; H = $tr.H; Tip = "$($f.Name)`n合計 $(Format-Size $f.Total)" })
        $ix = $tr.X + 2; $iy = $tr.Y + 14; $iw = $tr.W - 4; $ih = $tr.H - 16
        if ($iw -gt 2 -and $ih -gt 2) {
            $inItems = @($f.Files | ForEach-Object { [PSCustomObject]@{ Value = [double]$_.Length; Ref = $_ } })
            $inRects = @(TM-Squarify $inItems $ix $iy $iw $ih)
            foreach ($irec in $inRects) {
                $it = $irec.Item.Ref
                $ln = $it.BaseName.ToLowerInvariant()
                $brush = $script:tmBrushOther
                if ($ln.StartsWith('zh_tw')) { $brush = $script:tmBrushTw }
                elseif ($ln.StartsWith('zh_cn')) { $brush = $script:tmBrushCn }
                $rf = [System.Drawing.RectangleF]::new($irec.X, $irec.Y, $irec.W, $irec.H)
                $rf.Inflate(-0.5, -0.5)
                $g.FillRectangle($brush, $rf)
                if ($irec.W -gt 36 -and $irec.H -gt 13) {
                    $lf = [System.Drawing.RectangleF]::new($irec.X + 2, $irec.Y + 1, $irec.W - 4, $irec.H - 2)
                    $g.DrawString($it.BaseName, $script:tmFontSmall, $script:tmBrushText, $lf)
                }
                $null = $script:tmHit.Add([PSCustomObject]@{ X = $irec.X; Y = $irec.Y; W = $irec.W; H = $irec.H; Tip = "$($it.Path)`n$($it.BaseName) — $(Format-Size $it.Length)" })
            }
        }
    }
}

function New-TreemapForm {
    $script:tmForm = New-Object System.Windows.Forms.Form
    $script:tmForm.Text = "樹狀圖（面積＝檔案大小，顏色＝語系）"
    $script:tmForm.Size = New-Object System.Drawing.Size(900, 620)
    $script:tmForm.StartPosition = "CenterParent"
    $script:tmForm.MinimumSize = New-Object System.Drawing.Size(480, 320)
    $script:tmPanel = New-Object System.Windows.Forms.Panel
    $script:tmPanel.Dock = "Fill"
    $null = $script:tmPanel.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic').SetValue($script:tmPanel, $true, $null)
    $script:tmForm.Controls.Add($script:tmPanel)
    $script:tmTip = New-Object System.Windows.Forms.ToolTip
    $script:tmHit = New-Object System.Collections.Generic.List[object]
    $script:tmLastTip = ''
    $script:tmForm.Owner = $form

    $script:tmPanel.Add_Paint({
        TM-Draw $_.Graphics $script:tmPanel.ClientSize.Width $script:tmPanel.ClientSize.Height
    })
    $script:tmPanel.Add_MouseMove({
        $x = $_.X; $y = $_.Y; $tip = ''
        for ($k = $script:tmHit.Count - 1; $k -ge 0; $k--) {
            $h = $script:tmHit[$k]
            if ($x -ge $h.X -and $x -le ($h.X + $h.W) -and $y -ge $h.Y -and $y -le ($h.Y + $h.H)) { $tip = $h.Tip; break }
        }
        if ($tip -ne $script:tmLastTip) {
            $script:tmTip.SetToolTip($script:tmPanel, $tip)
            $script:tmLastTip = $tip
        }
    })
    $script:tmPanel.Add_MouseLeave({
        $script:tmTip.SetToolTip($script:tmPanel, '')
        $script:tmLastTip = ''
    })
    $script:tmPanel.Add_Resize({ $script:tmPanel.Invalidate() })
}

function Show-Treemap {
    if ($script:resultsData.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($form, "請先掃描出結果再開樹狀圖。", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    if (-not $script:tmForm -or $script:tmForm.IsDisposed) { New-TreemapForm }
    $null = $script:tmForm.Show()
    $script:tmForm.Activate()
    $script:tmPanel.Invalidate()
}

$btnTreemap.Add_Click({ Show-Treemap })

# ---------- 事件 ----------
$btnScan.Add_Click({ Start-Scan })

foreach ($tb in @($txtPath, $txtPattern, $txtExcl)) {
    $tb.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            Start-Scan
        }
    })
}

function Add-DropHandlers($control) {
    $control.AllowDrop = $true
    $control.Add_DragEnter({ $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy })
    $control.Add_DragDrop({
        if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $paths = $_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
            if ($paths.Count -gt 0) {
                $txtPath.Text = $paths[0]
                if (-not $script:scanning) { Start-Scan }
            }
        }
    })
}
Add-DropHandlers $txtPath
Add-DropHandlers $form

$lv.Add_ColumnClick({
    $field = @{0 = 'No'; 1 = 'Type'; 2 = 'BaseName'; 3 = 'Length'; 4 = 'MTime'; 5 = 'Path'}[[int]$_.Column]
    if (-not $field -or $script:resultsData.Count -eq 0) { return }
    if ($script:sortField -eq $field) { $script:sortDesc = -not $script:sortDesc }
    else { $script:sortField = $field; $script:sortDesc = $false }
    $script:resultsData = @($script:resultsData | Sort-Object -Property $field -Descending:$script:sortDesc)
    Show-Results
})

$btnCopy.Add_Click({
    if ($script:resultsData.Count -eq 0) { return }
    $paths = ($script:resultsData | ForEach-Object { $_.Path }) -join "`r`n"
    try {
        Set-Clipboard -Value $paths
        [System.Windows.Forms.MessageBox]::Show($form, "已複製 $($script:resultsData.Count) 個完整路徑到剪貼簿。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($form, "複製失敗：$($_.Exception.Message)", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$btnExport.Add_Click({
    if ($script:resultsData.Count -eq 0) { return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "CSV 檔案 (*.csv)|*.csv|所有檔案 (*.*)|*.*"
    $sfd.FileName = "zh_cn_掃描結果.csv"
    if ($sfd.ShowDialog($form) -ne 'OK') { return }
    try {
        $script:resultsData |
            Select-Object @{n = 'No'; e = { $_.No } },
                           @{n = '類型'; e = { $_.Type } },
                           @{n = '主檔名'; e = { $_.BaseName } },
                           @{n = '大小Bytes'; e = { $_.Length } },
                           @{n = '修改時間'; e = { if ($_.MTime) { $_.MTime.ToString('yyyy/MM/dd HH:mm') } else { '' } } },
                           @{n = '完整路徑'; e = { $_.Path } } |
            Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8
        [System.Windows.Forms.MessageBox]::Show($form, "已匯出 $($script:resultsData.Count) 筆到：`n$($sfd.FileName)", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($form, "匯出失敗：$($_.Exception.Message)", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$btnOpenFile.Add_Click({
    if ($lv.SelectedItems.Count -eq 0) { return }
    $path = $lv.SelectedItems[0].SubItems[5].Text
    if (Test-Path $path) { Invoke-Item -Path $path }
})

$btnOpenContaining.Add_Click({
    if ($lv.SelectedItems.Count -eq 0) { return }
    $path = $lv.SelectedItems[0].SubItems[5].Text
    $item = Get-Item -Path $path -ErrorAction SilentlyContinue
    if (-not $item) { return }
    $target = if ($item.PSIsContainer) { $path } else { Split-Path -Path $path -Parent }
    if (Test-Path $target) { Invoke-Item -Path $target }
})

$lv.Add_DoubleClick({
    $btnOpenContaining.PerformClick()
})

$form.Add_FormClosing({
    if ($script:scanning -and $script:scanSync) { $script:scanSync.Cancel = $true }
    if ($script:tmForm -and -not $script:tmForm.IsDisposed) { $script:tmForm.Close() }
    try {
        $settings.Path = $txtPath.Text
        $settings.Pattern = $txtPattern.Text
        $settings.Excludes = $txtExcl.Text
        if ($form.WindowState -eq 'Normal') {
            $settings.Left = $form.Left
            $settings.Top = $form.Top
            $settings.Width = $form.Width
            $settings.Height = $form.Height
            $settings.Maximized = $false
        } else {
            $settings.Maximized = ($form.WindowState -eq 'Maximized')
        }
        $settings | ConvertTo-Json | Set-Content -Path $script:settingsPath -Encoding UTF8
    } catch { }
})

[void]$form.ShowDialog()
Cleanup-Scan