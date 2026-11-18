Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppVersion = '1.3.1'
$script:AppRoot = if ($env:DFC_SCRIPT) { Split-Path -Parent $env:DFC_SCRIPT } else { $PSScriptRoot }
$script:BrandLogoPath = Join-Path $script:AppRoot 'assets\33works-logo.png'
$script:BrandIconPath = Join-Path $script:AppRoot 'assets\33works.ico'
$script:OfficialLineUrl = 'https://lin.ee/Pr5T1EH'
$script:EcpayUrl = 'https://payment.ecpay.com.tw/QuickCollect/PayData?UV8kunudvpag0i8o5BpVheak%2blji826yhTg%2f3%2bI2iDo%3d'
$script:Groups = @()
$script:CurrentIndex = 0
$script:Resolved = @{}
$script:SelectedKeep = $null
$script:PreviewImage = $null
$script:BrandHeaderImage = $null

function Open-ExternalUrl([string]$Url, [string]$Name) {
    try {
        Start-Process -FilePath $Url
    } catch {
        Show-ErrorMessage "無法開啟$Name：`r`n$($_.Exception.Message)"
    }
}

function Show-Info([string]$Message, [string]$Title = '重複檔案整理工具') {
    [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-Warning([string]$Message, [string]$Title = '重複檔案整理工具') {
    [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

function Show-ErrorMessage([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show(
        $Message, '重複檔案整理工具',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Format-FileSize([Int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} 位元組' -f $Bytes)
}

function Get-ExactHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Add-ActionLog([string]$Text) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text)
    Add-Content -LiteralPath $script:ActionLogPath -Value $line -Encoding UTF8
}

function Get-PreviewBitmap([string]$Path) {
    $imageExtensions = @('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff')
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    if ($imageExtensions -contains $extension) {
        $stream = $null
        $sourceImage = $null
        try {
            $stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )
            $sourceImage = [System.Drawing.Image]::FromStream($stream)
            return [System.Drawing.Bitmap]::new($sourceImage)
        } finally {
            if ($null -ne $sourceImage) { $sourceImage.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }

    $icon = $null
    try {
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
        if ($null -ne $icon) { return $icon.ToBitmap() }
    } finally {
        if ($null -ne $icon) { $icon.Dispose() }
    }
    return $null
}

function Export-InitialReports($Groups, [string]$RootPath, [string]$ReportFolder) {
    # Windows PowerShell 5.1 對 Generic List 轉陣列偶爾會出現
    # "Argument types do not match"，因此一律使用原生 PowerShell 陣列。
    $rows = @(
        foreach ($group in $Groups) {
            $copyNumber = 0
            foreach ($item in ($group.Files | Sort-Object FullPath)) {
                $copyNumber++
                [PSCustomObject]@{
                    '重複組別'       = $group.Id
                    '組內順序'       = $copyNumber
                    '檔名'           = $item.Name
                    '副檔名'         = $item.Extension
                    '大小（位元組）' = $item.SizeBytes
                    '大小'           = Format-FileSize $item.SizeBytes
                    '修改日期'       = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                    '完整位置'       = $item.FullPath
                    'SHA-256'        = $item.Hash
                }
            }
        }
    )

    $csvPath = Join-Path $ReportFolder '重複檔案清單.csv'
    $htmlPath = Join-Path $ReportFolder '重複檔案清單.html'
    $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    $style = @'
<style>
body { font-family: "Microsoft JhengHei", "Segoe UI", sans-serif; margin: 24px; color: #202124; }
h1 { font-size: 24px; }
.good { background: #e8f5e9; border-left: 5px solid #2e7d32; padding: 12px 16px; margin: 16px 0; }
table { border-collapse: collapse; width: 100%; font-size: 14px; }
th { position: sticky; top: 0; background: #245b78; color: white; }
th, td { border: 1px solid #d0d7de; padding: 7px; text-align: left; vertical-align: top; }
tr:nth-child(even) { background: #f6f8fa; }
</style>
'@
    $fileCount = ($Groups | ForEach-Object { $_.Files.Count } | Measure-Object -Sum).Sum
    $summary = "掃描位置：$RootPath<br>完全相同的重複組：$($Groups.Count) 組<br>列出的檔案：$fileCount 個"
    $preContent = "<h1>重複檔案檢查報告</h1><p>$summary</p><div class='good'><strong>判定：</strong>同組檔案已使用副檔名、大小及 SHA-256 實際內容核對，並非只比較檔名。</div>"
    $rows | ConvertTo-Html -Head $style -PreContent $preContent -Title '重複檔案檢查報告' | Set-Content -LiteralPath $htmlPath -Encoding UTF8
}

function New-ProgressWindow {
    $window = New-Object System.Windows.Forms.Form
    $window.Text = '正在檢查重複檔案'
    $window.Size = New-Object System.Drawing.Size(620, 180)
    $window.StartPosition = 'CenterScreen'
    $window.FormBorderStyle = 'FixedDialog'
    $window.MaximizeBox = $false
    $window.MinimizeBox = $false
    $window.TopMost = $true
    if (Test-Path -LiteralPath $script:BrandIconPath -PathType Leaf) {
        $window.Icon = [System.Drawing.Icon]::new($script:BrandIconPath)
    }

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(24, 22)
    $label.Size = New-Object System.Drawing.Size(555, 46)
    $label.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)
    $label.Text = '正在讀取資料夾，請稍候……'

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(24, 82)
    $bar.Size = New-Object System.Drawing.Size(555, 24)
    $bar.Minimum = 0
    $bar.Maximum = 100
    $bar.Style = 'Marquee'

    $window.Controls.Add($label)
    $window.Controls.Add($bar)
    return [PSCustomObject]@{ Form = $window; Label = $label; Bar = $bar }
}

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderDialog.Description = '選擇要檢查的資料夾（包含所有子資料夾）'
$folderDialog.ShowNewFolderButton = $false

if ($folderDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    exit 0
}

$rootPath = $folderDialog.SelectedPath
$timeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$desktopPath = [Environment]::GetFolderPath('Desktop')
$reportFolder = Join-Path $desktopPath "重複檔案檢查_$timeStamp"
New-Item -Path $reportFolder -ItemType Directory -Force | Out-Null
$script:ReportFolder = $reportFolder
$script:ActionLogPath = Join-Path $reportFolder '處理紀錄.txt'
$readErrorPath = Join-Path $reportFolder '無法讀取的檔案.txt'
Set-Content -LiteralPath $script:ActionLogPath -Value "重複檔案整理工具 V$($script:AppVersion) 處理紀錄`r`n掃描位置：$rootPath`r`n" -Encoding UTF8

$progress = New-ProgressWindow
$progress.Form.Show()
[System.Windows.Forms.Application]::DoEvents()

try {
    $progress.Label.Text = '正在列出資料夾內的檔案……'
    [System.Windows.Forms.Application]::DoEvents()
    $allFiles = @(Get-ChildItem -LiteralPath $rootPath -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable scanErrors)

    if ($scanErrors) {
        $scanErrors | ForEach-Object { $_.Exception.Message } | Set-Content -LiteralPath $readErrorPath -Encoding UTF8
    }

    $progress.Label.Text = "找到 $($allFiles.Count) 個檔案，正在篩選可能重複的項目……"
    [System.Windows.Forms.Application]::DoEvents()

    $candidates = @(
        $allFiles |
            Group-Object { ('{0}|{1}' -f $_.Extension.ToLowerInvariant(), $_.Length) } |
            Where-Object { $_.Count -gt 1 } |
            ForEach-Object { $_.Group }
    )

    $hashErrors = @()
    $candidateCount = $candidates.Count
    $progress.Bar.Style = 'Continuous'

    $index = 0
    $hashedFiles = @(
        foreach ($file in $candidates) {
            $index++
            $percent = if ($candidateCount -eq 0) { 100 } else { [int]($index * 100 / $candidateCount) }
            $progress.Bar.Value = [Math]::Min(100, [Math]::Max(0, $percent))
            $progress.Label.Text = "正在核對實際內容：$index / $candidateCount`r`n$($file.Name)"
            [System.Windows.Forms.Application]::DoEvents()

            try {
                $hash = Get-ExactHash $file.FullName
                [PSCustomObject]@{
                    Extension     = $file.Extension.ToLowerInvariant()
                    SizeBytes     = [Int64]$file.Length
                    Hash          = $hash
                    Name          = $file.Name
                    FullPath      = $file.FullName
                    Directory     = $file.DirectoryName
                    LastWriteTime = $file.LastWriteTime
                }
            } catch {
                $hashErrors += "$($file.FullName) | $($_.Exception.Message)"
            }
        }
    )

    if ($hashErrors.Count -gt 0) {
        $hashErrors | Add-Content -LiteralPath $readErrorPath -Encoding UTF8
    }

    $rawGroups = @(
        $hashedFiles |
            Group-Object { ('{0}|{1}|{2}' -f $_.Extension, $_.SizeBytes, $_.Hash) } |
            Where-Object { $_.Count -gt 1 } |
            Sort-Object { $_.Group[0].SizeBytes * ($_.Count - 1) } -Descending
    )

    $groupNumber = 0
    $groups = @(
        foreach ($rawGroup in $rawGroups) {
            $groupNumber++
            $first = $rawGroup.Group[0]
            [PSCustomObject]@{
                Id        = $groupNumber
                Hash      = $first.Hash
                Extension = $first.Extension
                SizeBytes = $first.SizeBytes
                Files     = @($rawGroup.Group | Sort-Object FullPath)
            }
        }
    )
    $script:Groups = $groups
} catch {
    $progress.Form.Close()
    $scanErrorPath = Join-Path $reportFolder '掃描錯誤.txt'
    $errorPosition = if ($null -ne $_.InvocationInfo) { $_.InvocationInfo.PositionMessage } else { '無法取得錯誤位置' }
    $errorStack = if ($_.ScriptStackTrace) { $_.ScriptStackTrace } else { '無法取得程式堆疊' }
    @(
        "重複檔案整理工具 V$($script:AppVersion)"
        "發生時間：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "掃描位置：$rootPath"
        ''
        "錯誤訊息：$($_.Exception.Message)"
        "錯誤類型：$($_.Exception.GetType().FullName)"
        ''
        '錯誤位置：'
        $errorPosition
        ''
        '程式堆疊：'
        $errorStack
        ''
        '完整錯誤：'
        ($_ | Out-String)
    ) | Set-Content -LiteralPath $scanErrorPath -Encoding UTF8
    Show-ErrorMessage "掃描時發生錯誤：`r`n$($_.Exception.Message)`r`n`r`n詳細資料已寫入：`r`n$scanErrorPath"
    exit 1
}

$progress.Form.Close()
$progress.Form.Dispose()

if ($script:Groups.Count -eq 0) {
    $resultPath = Join-Path $reportFolder '檢查結果.txt'
    @(
        '沒有找到內容完全相同的重複檔案。'
        "掃描位置：$rootPath"
        "掃描檔案：$($allFiles.Count) 個"
        "檢查時間：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Start-Process -FilePath $reportFolder
    Show-Info "檢查完成。`r`n`r`n沒有找到副檔名、大小及內容皆完全相同的重複檔案。"
    exit 0
}

Export-InitialReports $script:Groups $rootPath $reportFolder
Add-ActionLog "掃描完成：$($script:Groups.Count) 組完全相同的重複檔案。"

# 主視覺介面
$form = New-Object System.Windows.Forms.Form
$form.Text = "重複檔案整理工具 V$($script:AppVersion)"
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.MinimumSize = New-Object System.Drawing.Size(980, 650)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = 'Dpi'
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)
if (Test-Path -LiteralPath $script:BrandIconPath -PathType Leaf) {
    $form.Icon = [System.Drawing.Icon]::new($script:BrandIconPath)
}

$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mainLayout.Dock = 'Fill'
$mainLayout.ColumnCount = 1
$mainLayout.RowCount = 3
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 125)))
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 125)))

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Fill'
$header.BackColor = [System.Drawing.Color]::White

$brandPicture = New-Object System.Windows.Forms.PictureBox
$brandPicture.Location = New-Object System.Drawing.Point(20, 15)
$brandPicture.Size = New-Object System.Drawing.Size(78, 78)
$brandPicture.SizeMode = 'Zoom'
if (Test-Path -LiteralPath $script:BrandLogoPath -PathType Leaf) {
    $script:BrandHeaderImage = Get-PreviewBitmap $script:BrandLogoPath
    $brandPicture.Image = $script:BrandHeaderImage
}

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Location = New-Object System.Drawing.Point(112, 14)
$titleLabel.Size = New-Object System.Drawing.Size(610, 32)
$titleLabel.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.Text = '重複檔案比較'

$groupStatusLabel = New-Object System.Windows.Forms.Label
$groupStatusLabel.Location = New-Object System.Drawing.Point(114, 50)
$groupStatusLabel.Size = New-Object System.Drawing.Size(610, 25)
$groupStatusLabel.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)

$rootLabel = New-Object System.Windows.Forms.Label
$rootLabel.Location = New-Object System.Drawing.Point(114, 82)
$rootLabel.Size = New-Object System.Drawing.Size(625, 21)
$rootLabel.Anchor = 'Left,Right,Top'
$rootLabel.AutoEllipsis = $true
$rootLabel.ForeColor = [System.Drawing.Color]::DimGray
$rootLabel.Text = "掃描位置：$rootPath"

$badge = New-Object System.Windows.Forms.Label
$badge.Location = New-Object System.Drawing.Point(790, 14)
$badge.Size = New-Object System.Drawing.Size(340, 38)
$badge.Anchor = 'Top,Right'
$badge.TextAlign = 'MiddleCenter'
$badge.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10, [System.Drawing.FontStyle]::Bold)
$badge.BackColor = [System.Drawing.Color]::FromArgb(225, 245, 230)
$badge.ForeColor = [System.Drawing.Color]::FromArgb(25, 110, 55)
$badge.Text = '✓ 實際內容 100% 完全相同'

$lineButton = New-Object System.Windows.Forms.Button
$lineButton.Location = New-Object System.Drawing.Point(790, 65)
$lineButton.Size = New-Object System.Drawing.Size(160, 36)
$lineButton.Anchor = 'Top,Right'
$lineButton.Text = '加入官方 LINE'
$lineButton.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9, [System.Drawing.FontStyle]::Bold)
$lineButton.BackColor = [System.Drawing.Color]::FromArgb(6, 199, 85)
$lineButton.ForeColor = [System.Drawing.Color]::White
$lineButton.FlatStyle = 'Flat'

$supportButton = New-Object System.Windows.Forms.Button
$supportButton.Location = New-Object System.Drawing.Point(960, 65)
$supportButton.Size = New-Object System.Drawing.Size(170, 36)
$supportButton.Anchor = 'Top,Right'
$supportButton.Text = '支持 33 Works'
$supportButton.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9, [System.Drawing.FontStyle]::Bold)
$supportButton.BackColor = [System.Drawing.Color]::FromArgb(24, 52, 100)
$supportButton.ForeColor = [System.Drawing.Color]::FromArgb(255, 207, 75)
$supportButton.FlatStyle = 'Flat'

$lineButton.Add_Click({ Open-ExternalUrl $script:OfficialLineUrl '官方 LINE' })
$supportButton.Add_Click({ Open-ExternalUrl $script:EcpayUrl '綠界支持頁面' })

[void]$header.Controls.Add($brandPicture)
[void]$header.Controls.Add($titleLabel)
[void]$header.Controls.Add($groupStatusLabel)
[void]$header.Controls.Add($rootLabel)
[void]$header.Controls.Add($badge)
[void]$header.Controls.Add($lineButton)
[void]$header.Controls.Add($supportButton)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Vertical'
$split.SplitterDistance = 760
$split.Panel1.Padding = New-Object System.Windows.Forms.Padding(18, 14, 8, 10)
$split.Panel2.Padding = New-Object System.Windows.Forms.Padding(8, 14, 18, 10)

$leftLayout = New-Object System.Windows.Forms.TableLayoutPanel
$leftLayout.Dock = 'Fill'
$leftLayout.ColumnCount = 1
$leftLayout.RowCount = 3
$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 55)))
$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$leftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 46)))

$explainLabel = New-Object System.Windows.Forms.Label
$explainLabel.Dock = 'Fill'
$explainLabel.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)
$explainLabel.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 75)
$explainLabel.Text = '這些檔案內容完全一樣，只有名稱或存放位置不同。請點選你真正要保留的那一份。'

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.BorderStyle = 'Fixed3D'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.ReadOnly = $true
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.AutoGenerateColumns = $false
$grid.AutoSizeRowsMode = 'AllCells'
$grid.DefaultCellStyle.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9)
$grid.DefaultCellStyle.WrapMode = 'False'
$grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9, [System.Drawing.FontStyle]::Bold)
$grid.ColumnHeadersHeight = 34
$grid.RowTemplate.Height = 34

$nameColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$nameColumn.HeaderText = '檔名'
$nameColumn.Width = 180
$sizeColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$sizeColumn.HeaderText = '大小'
$sizeColumn.Width = 90
$dateColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$dateColumn.HeaderText = '修改日期'
$dateColumn.Width = 145
$pathColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$pathColumn.HeaderText = '完整位置'
$pathColumn.AutoSizeMode = 'Fill'
[void]$grid.Columns.Add($nameColumn)
[void]$grid.Columns.Add($sizeColumn)
[void]$grid.Columns.Add($dateColumn)
[void]$grid.Columns.Add($pathColumn)

$fileButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$fileButtons.Dock = 'Fill'
$fileButtons.FlowDirection = 'LeftToRight'
$fileButtons.Padding = New-Object System.Windows.Forms.Padding(0, 7, 0, 0)

$openFileButton = New-Object System.Windows.Forms.Button
$openFileButton.Size = New-Object System.Drawing.Size(130, 32)
$openFileButton.Text = '開啟檔案'
$openFileButton.Enabled = $false
$openFolderButton = New-Object System.Windows.Forms.Button
$openFolderButton.Size = New-Object System.Drawing.Size(150, 32)
$openFolderButton.Text = '顯示所在資料夾'
$openFolderButton.Enabled = $false
[void]$fileButtons.Controls.Add($openFileButton)
[void]$fileButtons.Controls.Add($openFolderButton)

$leftLayout.Controls.Add($explainLabel, 0, 0)
$leftLayout.Controls.Add($grid, 0, 1)
$leftLayout.Controls.Add($fileButtons, 0, 2)
$split.Panel1.Controls.Add($leftLayout)

$previewLayout = New-Object System.Windows.Forms.TableLayoutPanel
$previewLayout.Dock = 'Fill'
$previewLayout.ColumnCount = 1
$previewLayout.RowCount = 3
$previewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
$previewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$previewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 90)))

$previewTitle = New-Object System.Windows.Forms.Label
$previewTitle.Dock = 'Fill'
$previewTitle.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10, [System.Drawing.FontStyle]::Bold)
$previewTitle.Text = '檔案預覽'

$previewBox = New-Object System.Windows.Forms.PictureBox
$previewBox.Dock = 'Fill'
$previewBox.BackColor = [System.Drawing.Color]::White
$previewBox.BorderStyle = 'FixedSingle'
$previewBox.SizeMode = 'Zoom'

$previewInfo = New-Object System.Windows.Forms.Label
$previewInfo.Dock = 'Fill'
$previewInfo.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9)
$previewInfo.ForeColor = [System.Drawing.Color]::DimGray
$previewInfo.Padding = New-Object System.Windows.Forms.Padding(4, 8, 4, 4)
$previewInfo.AutoEllipsis = $true
$previewInfo.Text = '點選左側檔案後，可查看圖片縮圖或檔案類型。'

$previewLayout.Controls.Add($previewTitle, 0, 0)
$previewLayout.Controls.Add($previewBox, 0, 1)
$previewLayout.Controls.Add($previewInfo, 0, 2)
$split.Panel2.Controls.Add($previewLayout)

$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Dock = 'Fill'
$actionPanel.BackColor = [System.Drawing.Color]::White

$reclaimLabel = New-Object System.Windows.Forms.Label
$reclaimLabel.Location = New-Object System.Drawing.Point(22, 15)
$reclaimLabel.Size = New-Object System.Drawing.Size(650, 24)
$reclaimLabel.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10, [System.Drawing.FontStyle]::Bold)

$safetyLabel = New-Object System.Windows.Forms.Label
$safetyLabel.Location = New-Object System.Drawing.Point(22, 45)
$safetyLabel.Size = New-Object System.Drawing.Size(650, 42)
$safetyLabel.ForeColor = [System.Drawing.Color]::DimGray
$safetyLabel.Text = '安全設計：刪除前會重新核對內容；檔案只會移到 Windows 資源回收筒，不會永久刪除。'

$previousButton = New-Object System.Windows.Forms.Button
$previousButton.Location = New-Object System.Drawing.Point(22, 88)
$previousButton.Size = New-Object System.Drawing.Size(100, 30)
$previousButton.Text = '上一組'
$nextButton = New-Object System.Windows.Forms.Button
$nextButton.Location = New-Object System.Drawing.Point(130, 88)
$nextButton.Size = New-Object System.Drawing.Size(100, 30)
$nextButton.Text = '下一組'
$reportButton = New-Object System.Windows.Forms.Button
$reportButton.Location = New-Object System.Drawing.Point(238, 88)
$reportButton.Size = New-Object System.Drawing.Size(120, 30)
$reportButton.Text = '開啟報告資料夾'

$ignoreButton = New-Object System.Windows.Forms.Button
$ignoreButton.Size = New-Object System.Drawing.Size(145, 42)
$ignoreButton.Text = '全部保留／忽略'

$deleteOthersButton = New-Object System.Windows.Forms.Button
$deleteOthersButton.Size = New-Object System.Drawing.Size(205, 42)
$deleteOthersButton.Text = '保留選取項目，其餘移除'
$deleteOthersButton.BackColor = [System.Drawing.Color]::FromArgb(190, 55, 55)
$deleteOthersButton.ForeColor = [System.Drawing.Color]::White
$deleteOthersButton.FlatStyle = 'Flat'
$deleteOthersButton.Enabled = $false

$decisionButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$decisionButtons.Dock = 'Right'
$decisionButtons.Width = 390
$decisionButtons.FlowDirection = 'LeftToRight'
$decisionButtons.WrapContents = $false
$decisionButtons.Padding = New-Object System.Windows.Forms.Padding(10, 30, 10, 0)
[void]$decisionButtons.Controls.Add($ignoreButton)
[void]$decisionButtons.Controls.Add($deleteOthersButton)

[void]$actionPanel.Controls.Add($reclaimLabel)
[void]$actionPanel.Controls.Add($safetyLabel)
[void]$actionPanel.Controls.Add($previousButton)
[void]$actionPanel.Controls.Add($nextButton)
[void]$actionPanel.Controls.Add($reportButton)
[void]$actionPanel.Controls.Add($decisionButtons)

$mainLayout.Controls.Add($header, 0, 0)
$mainLayout.Controls.Add($split, 0, 1)
$mainLayout.Controls.Add($actionPanel, 0, 2)
$form.Controls.Add($mainLayout)

function Clear-Preview {
    $previewBox.Image = $null
    if ($null -ne $script:PreviewImage) {
        $script:PreviewImage.Dispose()
        $script:PreviewImage = $null
    }
}

function Set-SelectedPreview($Item) {
    Clear-Preview
    if ($null -eq $Item) {
        $previewInfo.Text = '點選左側檔案後，可查看圖片縮圖或檔案類型。'
        return
    }

    try {
        if (Test-Path -LiteralPath $Item.FullPath -PathType Leaf) {
            $script:PreviewImage = Get-PreviewBitmap $Item.FullPath
            $previewBox.Image = $script:PreviewImage
        }
    } catch {
        $previewBox.Image = $null
    }

    $previewInfo.Text = "檔名：$($Item.Name)`r`n大小：$(Format-FileSize $Item.SizeBytes)`r`n位置：$($Item.FullPath)"
}

function Get-UnresolvedCount {
    $count = 0
    foreach ($group in $script:Groups) {
        if (-not $script:Resolved.ContainsKey([string]$group.Id)) { $count++ }
    }
    return $count
}

function Find-NextGroupIndex([int]$StartIndex, [int]$Direction) {
    $count = $script:Groups.Count
    if ($count -eq 0) { return -1 }
    for ($offset = 1; $offset -le $count; $offset++) {
        $candidate = ($StartIndex + ($offset * $Direction)) % $count
        if ($candidate -lt 0) { $candidate += $count }
        $group = $script:Groups[$candidate]
        if (-not $script:Resolved.ContainsKey([string]$group.Id)) { return $candidate }
    }
    return -1
}

function Show-CompletedState {
    Clear-Preview
    $grid.Rows.Clear()
    $groupStatusLabel.Text = '所有重複群組都已完成選擇。'
    $reclaimLabel.Text = '處理完成。你可以開啟報告資料夾查看處理紀錄。'
    $explainLabel.Text = '已完成本次整理。需要重新檢查時，關閉工具後再執行一次即可。'
    $badge.Text = '✓ 本次處理完成'
    $deleteOthersButton.Enabled = $false
    $ignoreButton.Enabled = $false
    $previousButton.Enabled = $false
    $nextButton.Enabled = $false
    $openFileButton.Enabled = $false
    $openFolderButton.Enabled = $false
}

function Show-Group([int]$Index) {
    if ((Get-UnresolvedCount) -eq 0) {
        Show-CompletedState
        return
    }

    $script:CurrentIndex = $Index
    $group = $script:Groups[$Index]
    if ($script:Resolved.ContainsKey([string]$group.Id)) {
        $nextIndex = Find-NextGroupIndex $Index 1
        if ($nextIndex -lt 0) { Show-CompletedState; return }
        $script:CurrentIndex = $nextIndex
        $group = $script:Groups[$nextIndex]
    }

    $script:SelectedKeep = $null
    Clear-Preview
    $grid.Rows.Clear()
    foreach ($item in $group.Files) {
        $rowIndex = $grid.Rows.Add(
            $item.Name,
            (Format-FileSize $item.SizeBytes),
            $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),
            $item.FullPath
        )
        $grid.Rows[$rowIndex].Tag = $item
    }
    $grid.ClearSelection()

    $unresolved = Get-UnresolvedCount
    $groupStatusLabel.Text = "重複群組 $($group.Id)／$($script:Groups.Count)　｜　共 $($group.Files.Count) 份　｜　尚待處理 $unresolved 組"
    $reclaimBytes = [Int64]($group.SizeBytes * ($group.Files.Count - 1))
    $reclaimLabel.Text = "若只保留一份，可釋放 $(Format-FileSize $reclaimBytes)"
    $badge.Text = '✓ 實際內容 100% 完全相同'
    $deleteOthersButton.Enabled = $false
    $ignoreButton.Enabled = $true
    $previousButton.Enabled = $true
    $nextButton.Enabled = $true
    $openFileButton.Enabled = $false
    $openFolderButton.Enabled = $false
    $previewInfo.Text = '點選左側檔案後，可查看圖片縮圖或檔案類型。'
}

$grid.Add_SelectionChanged({
    if ($grid.SelectedRows.Count -eq 0) {
        $script:SelectedKeep = $null
        $deleteOthersButton.Enabled = $false
        $openFileButton.Enabled = $false
        $openFolderButton.Enabled = $false
        Set-SelectedPreview $null
        return
    }
    $item = $grid.SelectedRows[0].Tag
    $script:SelectedKeep = $item
    $deleteOthersButton.Enabled = $true
    $openFileButton.Enabled = $true
    $openFolderButton.Enabled = $true
    Set-SelectedPreview $item
})

$openFileButton.Add_Click({
    if ($null -eq $script:SelectedKeep) { return }
    try { Start-Process -FilePath $script:SelectedKeep.FullPath }
    catch { Show-ErrorMessage "無法開啟檔案：`r`n$($_.Exception.Message)" }
})

$openFolderButton.Add_Click({
    if ($null -eq $script:SelectedKeep) { return }
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$($script:SelectedKeep.FullPath)`"" }
    catch { Show-ErrorMessage "無法開啟資料夾：`r`n$($_.Exception.Message)" }
})

$reportButton.Add_Click({
    try { Start-Process -FilePath $script:ReportFolder }
    catch { Show-ErrorMessage "無法開啟報告資料夾：`r`n$($_.Exception.Message)" }
})

$previousButton.Add_Click({
    $index = Find-NextGroupIndex $script:CurrentIndex -1
    if ($index -ge 0) { Show-Group $index }
})

$nextButton.Add_Click({
    $index = Find-NextGroupIndex $script:CurrentIndex 1
    if ($index -ge 0) { Show-Group $index }
})

$ignoreButton.Add_Click({
    $group = $script:Groups[$script:CurrentIndex]
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "這一組的 $($group.Files.Count) 份檔案都會保留，不會刪除。`r`n`r`n確定要忽略這一組嗎？",
        '全部保留／忽略',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:Resolved[[string]$group.Id] = 'ignored'
    Add-ActionLog "群組 $($group.Id)：使用者選擇全部保留／忽略。"
    $nextIndex = Find-NextGroupIndex $script:CurrentIndex 1
    if ($nextIndex -lt 0) { Show-CompletedState } else { Show-Group $nextIndex }
})

$deleteOthersButton.Add_Click({
    if ($null -eq $script:SelectedKeep) {
        Show-Warning '請先點選一份要保留的檔案。'
        return
    }

    $group = $script:Groups[$script:CurrentIndex]
    $keep = $script:SelectedKeep
    $targets = @($group.Files | Where-Object { $_.FullPath -ne $keep.FullPath })
    $reclaimBytes = [Int64](($targets | Measure-Object -Property SizeBytes -Sum).Sum)
    $message = @"
你選擇保留：
$($keep.FullPath)

其餘 $($targets.Count) 份檔案將移到 Windows 資源回收筒。
預計釋放：$(Format-FileSize $reclaimBytes)

執行前會再次確認每個檔案內容仍然完全相同。
確定繼續嗎？
"@

    $answer = [System.Windows.Forms.MessageBox]::Show(
        $message,
        '最後確認',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Clear-Preview
    try {
        if (-not (Test-Path -LiteralPath $keep.FullPath -PathType Leaf)) {
            throw "要保留的檔案已不存在：$($keep.FullPath)"
        }
        if ((Get-ExactHash $keep.FullPath) -ne $group.Hash) {
            throw '要保留的檔案內容已經變更，為了安全已停止處理。請重新掃描。'
        }
    } catch {
        Show-ErrorMessage $_.Exception.Message
        Set-SelectedPreview $keep
        return
    }

    $failedItems = @()
    $deletedCount = 0
    foreach ($target in $targets) {
        try {
            if (-not (Test-Path -LiteralPath $target.FullPath -PathType Leaf)) {
                Add-ActionLog "群組 $($group.Id)：檔案已不存在，略過：$($target.FullPath)"
                continue
            }
            $currentHash = Get-ExactHash $target.FullPath
            if ($currentHash -ne $group.Hash) {
                throw '檔案內容已改變，未移除。'
            }
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $target.FullPath,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
            $deletedCount++
            Add-ActionLog "群組 $($group.Id)：移到資源回收筒：$($target.FullPath)｜保留：$($keep.FullPath)"
        } catch {
            $failedItems += $target
            Add-ActionLog "群組 $($group.Id)：處理失敗：$($target.FullPath)｜原因：$($_.Exception.Message)"
        }
    }

    if ($failedItems.Count -eq 0) {
        $script:Resolved[[string]$group.Id] = 'deleted'
        Show-Info "處理完成。`r`n`r`n保留1份，$deletedCount 份已移到資源回收筒。"
        $nextIndex = Find-NextGroupIndex $script:CurrentIndex 1
        if ($nextIndex -lt 0) { Show-CompletedState } else { Show-Group $nextIndex }
    } else {
        $group.Files = @($keep) + @($failedItems)
        Show-Warning "部分完成：$deletedCount 份已移到資源回收筒，$($failedItems.Count) 份處理失敗。`r`n`r`n詳細原因已寫入處理紀錄。"
        Show-Group $script:CurrentIndex
    }
})

$form.Add_FormClosed({
    Clear-Preview
    if ($null -ne $script:BrandHeaderImage) {
        $script:BrandHeaderImage.Dispose()
        $script:BrandHeaderImage = $null
    }
})

Show-Group 0
[void]$form.ShowDialog()
exit 0
