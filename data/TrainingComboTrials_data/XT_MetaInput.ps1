Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "SilentlyContinue"
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Global\XT_MetaInput_SF6_TrainingComboTrials", [ref]$createdNew)
if (-not $createdNew) {
    exit
}

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$requestPath = Join-Path $baseDir "XT_SaveMetaRequest.json"
$bridgePath = Join-Path $baseDir "XT_SaveMetaBridge.json"
$lastRequestId = ""

function Read-RequestJson {
    if (-not (Test-Path -LiteralPath $requestPath)) { return $null }
    try {
        return Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-BridgeJson($payload) {
    $jsonText = $payload | ConvertTo-Json -Depth 8
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($bridgePath, $jsonText, $utf8NoBom)
}

function Show-MetaInputForm($request) {
    $requestId = [string]$request.request_id
    $defaultAuthor = [string]$request.default_author
    if ([string]::IsNullOrWhiteSpace($defaultAuthor)) { $defaultAuthor = "佚名" }

    $font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "保存连段训练信息"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size(520, 360)
    $form.Font = $font
    $form.TopMost = $true
    $script:completed = $false

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "训练名称（必填）"
    $titleLabel.Location = New-Object System.Drawing.Point(18, 20)
    $titleLabel.Size = New-Object System.Drawing.Size(140, 24)
    $form.Controls.Add($titleLabel)

    $titleBox = New-Object System.Windows.Forms.TextBox
    $titleBox.Location = New-Object System.Drawing.Point(160, 18)
    $titleBox.Size = New-Object System.Drawing.Size(320, 28)
    $form.Controls.Add($titleBox)

    $noteLabel = New-Object System.Windows.Forms.Label
    $noteLabel.Text = "备注"
    $noteLabel.Location = New-Object System.Drawing.Point(18, 62)
    $noteLabel.Size = New-Object System.Drawing.Size(140, 24)
    $form.Controls.Add($noteLabel)

    $noteBox = New-Object System.Windows.Forms.TextBox
    $noteBox.Location = New-Object System.Drawing.Point(160, 60)
    $noteBox.Size = New-Object System.Drawing.Size(320, 70)
    $noteBox.Multiline = $true
    $form.Controls.Add($noteBox)

    $authorLabel = New-Object System.Windows.Forms.Label
    $authorLabel.Text = "作者"
    $authorLabel.Location = New-Object System.Drawing.Point(18, 148)
    $authorLabel.Size = New-Object System.Drawing.Size(140, 24)
    $form.Controls.Add($authorLabel)

    $authorBox = New-Object System.Windows.Forms.TextBox
    $authorBox.Location = New-Object System.Drawing.Point(160, 146)
    $authorBox.Size = New-Object System.Drawing.Size(320, 28)
    $authorBox.Text = $defaultAuthor
    $form.Controls.Add($authorBox)

    $tagsLabel = New-Object System.Windows.Forms.Label
    $tagsLabel.Text = "标签（逗号分隔）"
    $tagsLabel.Location = New-Object System.Drawing.Point(18, 190)
    $tagsLabel.Size = New-Object System.Drawing.Size(140, 24)
    $form.Controls.Add($tagsLabel)

    $tagsBox = New-Object System.Windows.Forms.TextBox
    $tagsBox.Location = New-Object System.Drawing.Point(160, 188)
    $tagsBox.Size = New-Object System.Drawing.Size(320, 28)
    $form.Controls.Add($tagsBox)

    $errorLabel = New-Object System.Windows.Forms.Label
    $errorLabel.Text = ""
    $errorLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
    $errorLabel.Location = New-Object System.Drawing.Point(160, 226)
    $errorLabel.Size = New-Object System.Drawing.Size(320, 24)
    $form.Controls.Add($errorLabel)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = "保存"
    $saveButton.Location = New-Object System.Drawing.Point(280, 270)
    $saveButton.Size = New-Object System.Drawing.Size(90, 34)
    $form.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "取消"
    $cancelButton.Location = New-Object System.Drawing.Point(390, 270)
    $cancelButton.Size = New-Object System.Drawing.Size(90, 34)
    $form.Controls.Add($cancelButton)

    $saveButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($titleBox.Text)) {
            $errorLabel.Text = "请输入训练名称"
            return
        }

        $tags = @()
        foreach ($tag in ($tagsBox.Text -replace "，", "," -split ",")) {
            $clean = $tag.Trim()
            if ($clean.Length -gt 0) { $tags += $clean }
        }

        Write-BridgeJson @{
            request_id = $requestId
            action = "save"
            title = $titleBox.Text.Trim()
            note = $noteBox.Text.Trim()
            author = $authorBox.Text.Trim()
            tags = [object[]]$tags
            time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $script:completed = $true
        $form.Close()
    })

    $cancelButton.Add_Click({
        Write-BridgeJson @{
            request_id = $requestId
            action = "cancel"
            time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $script:completed = $true
        $form.Close()
    })

    $form.Add_FormClosing({
        if (-not $script:completed) {
            Write-BridgeJson @{
                request_id = $requestId
                action = "cancel"
                time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            $script:completed = $true
        }
    })

    $form.Add_Shown({ $titleBox.Focus() })
    [void]$form.ShowDialog()
}

[System.Windows.Forms.Application]::EnableVisualStyles()
while ($true) {
    $request = Read-RequestJson
    if ($request -and -not [string]::IsNullOrWhiteSpace([string]$request.request_id)) {
        $requestId = [string]$request.request_id
        if ($requestId -ne $lastRequestId) {
            $lastRequestId = $requestId
            Show-MetaInputForm $request
        }
    }
    Start-Sleep -Milliseconds 500
}
