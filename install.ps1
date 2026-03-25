#Requires -Version 5.1
<#
.SYNOPSIS
    claude-code-statusline 安裝腳本（Windows 版）

.DESCRIPTION
    將 statusline.ps1 安裝至 ~/.claude/ 目錄，
    並引導使用者設定 settings.json 的 statusLine 區段。

.NOTES
    用法：
      git clone https://github.com/kcchien/claude-code-statusline.git
      cd claude-code-statusline
      .\install.ps1

    不需要 jq — PowerShell 原生支援 JSON 操作。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════
# 路徑定義
# ═══════════════════════════════════════════════════════════════

$ScriptDir = $PSScriptRoot
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$TargetFile = Join-Path $ClaudeDir 'statusline.ps1'
$SettingsFile = Join-Path $ClaudeDir 'settings.json'
$SourceFile = Join-Path $ScriptDir 'statusline.ps1'

# ═══════════════════════════════════════════════════════════════
# 標頭
# ═══════════════════════════════════════════════════════════════

Write-Host ''
Write-Host ([char]0x25C6 + ' claude-code-statusline installer') -ForegroundColor Cyan
Write-Host ''

# ═══════════════════════════════════════════════════════════════
# 檢查是否在專案目錄內執行
# ═══════════════════════════════════════════════════════════════

if (-not (Test-Path $SourceFile)) {
    Write-Host '  Error: statusline.ps1 not found in current directory.' -ForegroundColor Red
    Write-Host '  Please run this script from the claude-code-statusline project root.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ═══════════════════════════════════════════════════════════════
# 建立 .claude 目錄（若不存在）
# ═══════════════════════════════════════════════════════════════

if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    Write-Host "  Created directory: $ClaudeDir" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════
# 複製 statusline.ps1 至目標位置
# ═══════════════════════════════════════════════════════════════

Copy-Item -Path $SourceFile -Destination $TargetFile -Force
Write-Host "  Installed to $TargetFile" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════
# statusLine 設定片段（供顯示用）
# ═══════════════════════════════════════════════════════════════

# 建議寫入 settings.json 的 statusLine 設定
$StatusLineSnippet = @'
  "statusLine": {
    "type": "command",
    "command": "powershell.exe -NoProfile -File ~/.claude/statusline.ps1",
    "timeout": 10
  }
'@

# 完整 settings.json 範例（檔案不存在時使用）
$FullSettingsJson = @'
{
  "statusLine": {
    "type": "command",
    "command": "powershell.exe -NoProfile -File ~/.claude/statusline.ps1",
    "timeout": 10
  }
}
'@

# ═══════════════════════════════════════════════════════════════
# 檢查並引導 settings.json 設定
# ═══════════════════════════════════════════════════════════════

Write-Host ''

if (Test-Path $SettingsFile) {
    # 讀取現有設定檔內容
    $settingsContent = Get-Content -Path $SettingsFile -Raw -ErrorAction SilentlyContinue

    if ($settingsContent -match '"statusLine"') {
        # 已有 statusLine 設定 — 詢問使用者是否覆蓋
        Write-Host '  Your settings.json already has a statusLine config.' -ForegroundColor Yellow
        Write-Host ''
        $answer = Read-Host '  Overwrite existing statusLine config? [y/N]'
        Write-Host ''
        if ($answer -match '^[Yy]$') {
            try {
                $settingsObj = $settingsContent | ConvertFrom-Json
                $statusLineObj = [PSCustomObject]@{
                    type    = 'command'
                    command = 'powershell.exe -NoProfile -File ~/.claude/statusline.ps1'
                    timeout = 10
                }
                $settingsObj.statusLine = $statusLineObj
                $settingsObj | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8
                Write-Host '  Updated statusLine config in settings.json' -ForegroundColor Green
            }
            catch {
                Write-Host "  Error updating settings.json: $_" -ForegroundColor Red
                Write-Host '  Please update it manually to:' -ForegroundColor Yellow
                Write-Host ''
                Write-Host $StatusLineSnippet -ForegroundColor White
            }
        }
        else {
            Write-Host '  Skipped. Your existing statusLine config was not changed.' -ForegroundColor DarkGray
        }
        Write-Host ''
    }
    else {
        # 設定檔存在但缺少 statusLine — 自動新增
        try {
            $settingsObj = $settingsContent | ConvertFrom-Json
            $statusLineObj = [PSCustomObject]@{
                type    = 'command'
                command = 'powershell.exe -NoProfile -File ~/.claude/statusline.ps1'
                timeout = 10
            }
            $settingsObj | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $statusLineObj
            $settingsObj | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8
            Write-Host '  Added statusLine config to settings.json' -ForegroundColor Green
        }
        catch {
            Write-Host "  Error updating settings.json: $_" -ForegroundColor Red
            Write-Host "  Please add this to your $SettingsFile :" -ForegroundColor Yellow
            Write-Host ''
            Write-Host $StatusLineSnippet -ForegroundColor White
        }
        Write-Host ''
    }
}
else {
    # 設定檔不存在 — 顯示完整範例
    Write-Host "  No settings.json found. Create $SettingsFile with:" -ForegroundColor White
    Write-Host ''
    Write-Host $FullSettingsJson -ForegroundColor White
    Write-Host ''
}

# ═══════════════════════════════════════════════════════════════
# 完成訊息
# ═══════════════════════════════════════════════════════════════

Write-Host ([char]0x2713 + ' Done! Restart Claude Code to see the status line.') -ForegroundColor Green
Write-Host ''
