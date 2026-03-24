# statusline.ps1 — Claude Code session status line (PowerShell 版)
#
# 兩行輸出：
#   第一行：◆ 模型 │ 漸層進度條 百分比 │ 費用 │ 時間 │ 速率限制
#   第二行：⎇分支* │ +增/-減 │ 目錄 │ ⚙ Agent
#
# 環境變數：
#   CLAUDE_STATUSLINE_ASCII=1     退回純 ASCII
#   CLAUDE_STATUSLINE_NERDFONT=1  啟用 Nerd Font 圖示
#   CLAUDE_STATUSLINE_POWERLINE=1 啟用 Powerline 分隔符（預設跟隨 NERDFONT）
#   COLORTERM=truecolor|24bit     系統自動設定，啟用真彩色漸層
#
# 用法：
#   Claude Code 透過 stdin 傳入 JSON，本腳本解析後輸出彩色狀態列至 stdout。
#   不需要 jq —— 使用 PowerShell 原生 ConvertFrom-Json。

# ═══════════════════════════════════════════════════════════════
# 編碼設定
# ═══════════════════════════════════════════════════════════════

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# ═══════════════════════════════════════════════════════════════
# 環境偵測
# ═══════════════════════════════════════════════════════════════

$USE_ASCII     = ($env:CLAUDE_STATUSLINE_ASCII -eq '1')
$USE_NERDFONT  = ($env:CLAUDE_STATUSLINE_NERDFONT -eq '1')
$USE_POWERLINE = $(if ($null -ne $env:CLAUDE_STATUSLINE_POWERLINE) {
    $env:CLAUDE_STATUSLINE_POWERLINE -eq '1'
} else {
    $USE_NERDFONT
})
$USE_TRUECOLOR = ($env:COLORTERM -eq 'truecolor') -or ($env:COLORTERM -eq '24bit')

# ═══════════════════════════════════════════════════════════════
# 色彩與符號
# ═══════════════════════════════════════════════════════════════

$e = [char]0x1b

$RST     = "$e[0m"
$CYAN    = "$e[36m"
$BLUE    = "$e[34m"
$GRAY    = "$e[90m"
$DIM     = "$e[2m"
$YELLOW  = "$e[33m"
$GREEN   = "$e[32m"
$RED     = "$e[31m"
$MAGENTA = "$e[35m"

# Anthropic 品牌紫 (#7266EA)
$PURPLE = $(if ($USE_TRUECOLOR) { "$e[38;2;114;102;234m" } else { "$e[35m" })

# 輔助函式：將超出 BMP 的 Unicode 碼點轉為 UTF-16 代理對字串
function ConvertTo-Utf16Char {
    param([int]$CodePoint)
    if ($CodePoint -le 0xFFFF) {
        return [string][char]$CodePoint
    }
    # UTF-16 代理對計算
    $cp = $CodePoint - 0x10000
    $high = [char](0xD800 + ($cp -shr 10))
    $low  = [char](0xDC00 + ($cp -band 0x3FF))
    return "$high$low"
}

# 符號集
if ($USE_ASCII) {
    $S_BRAND  = '<>'
    $S_BRANCH = '>'
    $S_WARN   = '!'
    $S_PROMPT = '>'
    $S_TIME   = ''
    $S_COST   = ''
    $SEP      = ' | '
}
elseif ($USE_NERDFONT) {
    $S_BRAND  = [char]0x25C6                                        # ◆
    $S_BRANCH = " $([char]0xE0A0)"                                  #  (Nerd Font branch)
    $S_WARN   = " $(ConvertTo-Utf16Char 0xF0026)"                   #  󰀦
    $S_PROMPT = [char]0x276F                                        # ❯
    $S_TIME   = "$(ConvertTo-Utf16Char 0xF0551) "                   # 󰔟
    $S_COST   = " $(ConvertTo-Utf16Char 0xF0485)"                   #  (Nerd Font dollar)
    $SEP      = $(if ($USE_POWERLINE) { "  " } else { " $([char]0x2502) " })
}
else {
    # Unicode（預設）
    $S_BRAND  = [char]0x25C6                                        # ◆
    $S_BRANCH = [char]0x2387                                        # ⎇
    $S_WARN   = " $([char]0x26A0)"                                  # ⚠
    $S_PROMPT = [char]0x276F                                        # ❯
    $S_TIME   = ''
    $S_COST   = ''
    $SEP      = $(if ($USE_POWERLINE) { "  " } else { " $([char]0x2502) " })
}

# ═══════════════════════════════════════════════════════════════
# 降級輸出
# ═══════════════════════════════════════════════════════════════

function Write-Fallback {
    param([string]$Message = [char]0x2500)
    [Console]::Out.Write("$GRAY$Message$RST")
    exit 0
}

# ═══════════════════════════════════════════════════════════════
# 讀取 JSON
# ═══════════════════════════════════════════════════════════════

try {
    $rawInput = [Console]::In.ReadToEnd()
}
catch {
    Write-Fallback "$([char]0x2500) $([char]0x2502) read error"
}

if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Fallback "$([char]0x2500) $([char]0x2502) empty input"
}

try {
    $json = $rawInput | ConvertFrom-Json
}
catch {
    Write-Fallback "$([char]0x2500) $([char]0x2502) parse error"
}

# ═══════════════════════════════════════════════════════════════
# JSON 欄位安全取值輔助函式
# ═══════════════════════════════════════════════════════════════

function Get-JsonStr {
    param($Obj, [string]$Path, [string]$Default = '')
    $parts = $Path -split '\.'
    $current = $Obj
    foreach ($part in $parts) {
        if ($null -eq $current) { return $Default }
        $current = $current.$part
    }
    if ($null -eq $current) { return $Default }
    return [string]$current
}

function Get-JsonNum {
    param($Obj, [string]$Path, [double]$Default = 0)
    $val = Get-JsonStr -Obj $Obj -Path $Path -Default ''
    if ($val -eq '') { return $Default }
    $num = 0.0
    if ([double]::TryParse($val, [ref]$num)) { return $num }
    return $Default
}

# ═══════════════════════════════════════════════════════════════
# 解析欄位
# ═══════════════════════════════════════════════════════════════

$modelName  = Get-JsonStr $json 'model.display_name'
$ctxPct     = Get-JsonNum $json 'context_window.used_percentage'
$ctxSize    = Get-JsonNum $json 'context_window.context_window_size'
$costUsd    = Get-JsonNum $json 'cost.total_cost_usd'
$durationMs = Get-JsonNum $json 'cost.total_duration_ms'
$linesAdd   = [int](Get-JsonNum $json 'cost.total_lines_added')
$linesRm    = [int](Get-JsonNum $json 'cost.total_lines_removed')
$cwdFull    = Get-JsonStr $json 'workspace.current_dir' -Default '.'
$branch     = Get-JsonStr $json 'worktree.branch'
$wtName     = Get-JsonStr $json 'worktree.name'
$rate5h     = Get-JsonNum $json 'rate_limits.five_hour.used_percentage' -Default -1
$rate7d     = Get-JsonNum $json 'rate_limits.seven_day.used_percentage' -Default -1
$agentName  = Get-JsonStr $json 'agent.name'

# 目錄短名
$dirName = $(if ($cwdFull -and $cwdFull -ne '.') {
    ($cwdFull -replace '\\', '/') -split '/' | Select-Object -Last 1
} else { '.' })

# ═══════════════════════════════════════════════════════════════
# 模型
# ═══════════════════════════════════════════════════════════════

$model = $(if ($modelName) { $modelName } else { [string]([char]0x2500) })

# ═══════════════════════════════════════════════════════════════
# 上下文進度條
# ═══════════════════════════════════════════════════════════════

$pctInt = [Math]::Max(0, [Math]::Min(100, [int][Math]::Floor($ctxPct)))
$barFilled = [Math]::Min(10, [int][Math]::Floor($pctInt / 10))

# 漸層色（真彩色）：綠 → 黃 → 橘 → 紅
$GRAD_R = @(46, 116, 186, 241, 239, 236, 233, 231, 211, 192)
$GRAD_G = @(204, 195, 186, 196, 161, 126, 101, 76, 66, 57)
$GRAD_B = @(113, 89, 64, 15, 24, 34, 44, 60, 50, 43)

$bar = ''
if ($USE_ASCII) {
    # ASCII 模式
    for ($i = 0; $i -lt 10; $i++) {
        $bar += $(if ($i -lt $barFilled) { '#' } else { '-' })
    }
}
elseif ($USE_TRUECOLOR) {
    # 真彩色漸層：每格獨立上色
    for ($i = 0; $i -lt 10; $i++) {
        if ($i -lt $barFilled) {
            $bar += "$e[38;2;$($GRAD_R[$i]);$($GRAD_G[$i]);$($GRAD_B[$i])m$([char]0x2588)"
        }
        else {
            $bar += "$e[38;2;60;60;60m$([char]0x2591)"
        }
    }
    $bar += $RST
}
else {
    # ANSI 退回：依整體百分比選色
    if ($pctInt -ge 90) { $barColor = $RED }
    elseif ($pctInt -ge 70) { $barColor = $YELLOW }
    else { $barColor = $GREEN }
    $barChars = ''
    for ($i = 0; $i -lt 10; $i++) {
        $barChars += $(if ($i -lt $barFilled) { [string][char]0x2588 } else { [string][char]0x2591 })
    }
    $bar = "$barColor$barChars$RST"
}

# 百分比文字顏色（跟進度條整體色一致）
if ($pctInt -ge 90) { $pctColor = $RED }
elseif ($pctInt -ge 70) { $pctColor = $YELLOW }
else { $pctColor = $GREEN }

# 警告符號（上下文 >= 90% 時顯示）
$ctxWarn = $(if ($pctInt -ge 90) { "$RED$S_WARN$RST" } else { '' })

# 上下文視窗大小（僅在 model display_name 不包含 context 資訊時才顯示）
$ctxLabel = ''
if ($model -notlike '*context*' -and $model -notlike '*Context*') {
    if ($ctxSize -ge 1000000) {
        $ctxLabel = " ${GRAY}1M${RST}"
    }
    elseif ($ctxSize -ge 200000) {
        $ctxLabel = " ${GRAY}200k${RST}"
    }
}

# ═══════════════════════════════════════════════════════════════
# 費用
# ═══════════════════════════════════════════════════════════════

$costFmt = '{0:F2}' -f $costUsd
if ($costUsd -ge 10) { $costColor = $RED }
elseif ($costUsd -ge 5) { $costColor = $YELLOW }
elseif ($costFmt -eq '0.00') { $costColor = $GRAY }
else { $costColor = $YELLOW }

# ═══════════════════════════════════════════════════════════════
# 經過時間（零值智慧隱藏）
# ═══════════════════════════════════════════════════════════════

$durSection = ''
if ($durationMs -gt 0) {
    $durSec = [int][Math]::Floor($durationMs / 1000)
    $durMin = [int][Math]::Floor($durSec / 60)
    $durS   = $durSec % 60
    if ($durMin -gt 0 -or $durS -gt 0) {
        $durSection = "${SEP}${GRAY}${S_TIME}${durMin}m${durS}s${RST}"
    }
}

# ═══════════════════════════════════════════════════════════════
# Git 分支與髒標記（帶快取）
# ═══════════════════════════════════════════════════════════════

$GIT_CACHE = Join-Path $env:TEMP 'claude-statusline-git-cache'
$GIT_CACHE_MAX_AGE = 5

$gitBranch = $branch
$dirty = ''

# 檢查快取是否過期
function Test-GitCacheStale {
    if (-not (Test-Path $GIT_CACHE)) { return $true }
    $cacheTime = (Get-Item $GIT_CACHE).LastWriteTime
    $age = (Get-Date) - $cacheTime
    return ($age.TotalSeconds -gt $GIT_CACHE_MAX_AGE)
}

# 將 cwd 正規化為本機路徑格式
$cwdLocal = $cwdFull -replace '/', '\'

if ($cwdLocal -and (Test-Path $cwdLocal -PathType Container)) {
    if (Test-GitCacheStale) {
        # 檢查是否為 Git 倉庫
        $gitDir = $null
        try {
            $gitDir = & git -C $cwdLocal rev-parse --git-dir 2>$null
        } catch {}

        if ($gitDir) {
            $cachedBranch = $gitBranch
            if (-not $cachedBranch) {
                try {
                    $cachedBranch = & git -C $cwdLocal -c core.useBuiltinFSMonitor=false branch --show-current 2>$null
                } catch {}
                if (-not $cachedBranch) {
                    try {
                        $cachedBranch = & git -C $cwdLocal rev-parse --short HEAD 2>$null
                    } catch {}
                }
            }

            $cachedDirty = ''
            $diffClean = $true
            $cachedClean = $true
            try {
                & git -C $cwdLocal -c core.useBuiltinFSMonitor=false diff --quiet 2>$null
                $diffClean = ($LASTEXITCODE -eq 0)
            } catch { $diffClean = $false }
            try {
                & git -C $cwdLocal -c core.useBuiltinFSMonitor=false diff --cached --quiet 2>$null
                $cachedClean = ($LASTEXITCODE -eq 0)
            } catch { $cachedClean = $false }

            if (-not $diffClean -or -not $cachedClean) {
                $cachedDirty = '*'
            }

            "$cachedBranch|$cachedDirty" | Out-File -FilePath $GIT_CACHE -Encoding utf8 -NoNewline
        }
        else {
            '|' | Out-File -FilePath $GIT_CACHE -Encoding utf8 -NoNewline
        }
    }

    # 讀取快取
    if (Test-Path $GIT_CACHE) {
        $cacheContent = (Get-Content $GIT_CACHE -Raw -Encoding utf8).Trim()
        $cacheParts = $cacheContent -split '\|', 2
        if (-not $gitBranch -and $cacheParts[0]) {
            $gitBranch = $cacheParts[0]
        }
        if ($cacheParts.Count -gt 1) {
            $dirty = $cacheParts[1]
        }
    }
}

# ═══════════════════════════════════════════════════════════════
# 行數增減（零值智慧隱藏）
# ═══════════════════════════════════════════════════════════════

$linesSection = ''
if ($linesAdd -gt 0 -or $linesRm -gt 0) {
    $linesSection = "${GREEN}+${linesAdd}${RST}/${RED}-${linesRm}${RST}"
}

# ═══════════════════════════════════════════════════════════════
# 速率限制（條件顯示）
# ═══════════════════════════════════════════════════════════════

$rate5hInt = [int][Math]::Floor($rate5h)
$rate7dInt = [int][Math]::Floor($rate7d)

$rateParts = ''
if ($rate5hInt -ge 0) {
    if ($rate5hInt -ge 80) { $rColor = $RED } else { $rColor = $GRAY }
    $rateParts += "${rColor}5h:${rate5hInt}%${RST}"
}
if ($rate7dInt -ge 0) {
    if ($rateParts) { $rateParts += ' ' }
    if ($rate7dInt -ge 80) { $rColor = $RED } else { $rColor = $GRAY }
    $rateParts += "${rColor}7d:${rate7dInt}%${RST}"
}

$rateSection = $(if ($rateParts) { "${SEP}${rateParts}" } else { '' })

# ═══════════════════════════════════════════════════════════════
# 組裝第一行
# ═══════════════════════════════════════════════════════════════

$line1  = "${PURPLE}${S_BRAND}${RST} ${CYAN}${model}${RST}"
$line1 += "${SEP}${bar} ${pctColor}${pctInt}%${RST}${ctxWarn}${ctxLabel}"
$line1 += "${SEP}${costColor}${S_COST}`$${costFmt}${RST}"
$line1 += $durSection
$line1 += $rateSection

# ═══════════════════════════════════════════════════════════════
# 組裝第二行
# ═══════════════════════════════════════════════════════════════

$parts = [System.Collections.Generic.List[string]]::new()

if ($gitBranch) {
    $parts.Add("${GRAY}${S_BRANCH}${gitBranch}${dirty}${RST}")
}
if ($linesSection) {
    $parts.Add($linesSection)
}
$parts.Add("${BLUE}${dirName}${RST}")

# Agent / Worktree 指示器（僅在非主 session 時顯示）
if ($wtName) {
    $parts.Add("${YELLOW}$([char]0x2699) worktree:${wtName}${RST}")
}
elseif ($agentName) {
    $parts.Add("${YELLOW}$([char]0x2699) ${agentName}${RST}")
}

$line2 = $parts -join $SEP

# ═══════════════════════════════════════════════════════════════
# 輸出
# ═══════════════════════════════════════════════════════════════

# 只輸出兩行（Claude Code 有自己的輸入提示符，不需要我們的 ❯）
[Console]::Out.Write("${line1}`n${line2}")
