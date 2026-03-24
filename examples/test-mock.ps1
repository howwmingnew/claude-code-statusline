#Requires -Version 5.1
<#
.SYNOPSIS
    測試 statusline.ps1 的模擬資料腳本

.DESCRIPTION
    以預設的模擬 JSON 資料餵入 statusline.ps1，
    驗證各種情境下的輸出是否正確。

.PARAMETER Scenario
    要執行的測試情境名稱。預設為 "all"（全部執行）。
    可用情境：normal, warning, danger, startup, agent, worktree, ascii, nerdfont

.EXAMPLE
    .\examples\test-mock.ps1
    .\examples\test-mock.ps1 normal
    .\examples\test-mock.ps1 danger
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('all', 'normal', 'warning', 'danger', 'startup', 'agent', 'worktree', 'ascii', 'nerdfont')]
    [string]$Scenario = 'all'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════
# 定位 statusline.ps1
# ═══════════════════════════════════════════════════════════════

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$StatuslineScript = Join-Path $ProjectRoot 'statusline.ps1'

if (-not (Test-Path $StatuslineScript)) {
    Write-Host "Error: $StatuslineScript not found." -ForegroundColor Red
    exit 1
}

# ═══════════════════════════════════════════════════════════════
# 測試執行函式
# ═══════════════════════════════════════════════════════════════

function Invoke-TestScenario {
    <#
    .SYNOPSIS
        執行單一測試情境：將模擬 JSON 透過管線傳送給 statusline.ps1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Json,
        [hashtable]$EnvOverrides = @{}
    )

    Write-Host ''
    # 分隔線標題
    Write-Host ([string]::new([char]0x2501, 3) + " $Label " + [string]::new([char]0x2501, 3))

    # 儲存原始環境變數，以便測試後還原
    $savedEnv = @{}
    foreach ($key in $EnvOverrides.Keys) {
        $savedEnv[$key] = [System.Environment]::GetEnvironmentVariable($key, 'Process')
        [System.Environment]::SetEnvironmentVariable($key, $EnvOverrides[$key], 'Process')
    }

    try {
        # 將 JSON 透過管線傳入 statusline.ps1
        $Json | pwsh -NoProfile -File $StatuslineScript
    }
    catch {
        Write-Host "  Error running test: $_" -ForegroundColor Red
    }
    finally {
        # 還原環境變數
        foreach ($key in $savedEnv.Keys) {
            [System.Environment]::SetEnvironmentVariable($key, $savedEnv[$key], 'Process')
        }
    }

    Write-Host ''
}

# ═══════════════════════════════════════════════════════════════
# 模擬測試資料
# ═══════════════════════════════════════════════════════════════

# 正常情境：42% 上下文、低費用、穩定使用中
$JsonNormal = @'
{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":42,"context_window_size":1000000},"cost":{"total_cost_usd":0.85,"total_lines_added":150,"total_lines_removed":30,"total_duration_ms":222000},"workspace":{"current_dir":"C:/Users/dev/my-project"},"worktree":{"branch":"main"},"rate_limits":{"five_hour":{"used_percentage":15},"seven_day":{"used_percentage":8}}}
'@

# 警告情境：75% 上下文、中等費用、接近限制
$JsonWarning = @'
{"model":{"display_name":"Claude Sonnet 4.6"},"context_window":{"used_percentage":75,"context_window_size":200000},"cost":{"total_cost_usd":3.20,"total_lines_added":280,"total_lines_removed":45,"total_duration_ms":725000},"workspace":{"current_dir":"C:/Users/dev/my-project"},"worktree":{"branch":"feat/auth"},"rate_limits":{"five_hour":{"used_percentage":48}}}
'@

# 危險情境：92% 上下文、高費用、速率限制接近上限
$JsonDanger = @'
{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":92,"context_window_size":1000000},"cost":{"total_cost_usd":15.30,"total_lines_added":500,"total_lines_removed":120,"total_duration_ms":2712000},"workspace":{"current_dir":"C:/Users/dev/api-server"},"worktree":{"branch":"main"},"rate_limits":{"five_hour":{"used_percentage":85},"seven_day":{"used_percentage":62}}}
'@

# 啟動情境：剛開始的 session，所有數值為零
$JsonStartup = @'
{"model":{"display_name":"Opus 4.6 (1M context)"},"context_window":{"used_percentage":0,"context_window_size":1000000},"cost":{"total_cost_usd":0,"total_duration_ms":0},"workspace":{"current_dir":"C:/Users/dev/my-project"}}
'@

# Agent 情境：使用 code-reviewer 代理
$JsonAgent = @'
{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":42,"context_window_size":1000000},"cost":{"total_cost_usd":0.85,"total_lines_added":150,"total_lines_removed":30,"total_duration_ms":222000},"workspace":{"current_dir":"C:/Users/dev/my-project"},"worktree":{"branch":"main"},"agent":{"name":"code-reviewer"}}
'@

# Worktree 情境：在 Git worktree 中工作
$JsonWorktree = @'
{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":42,"context_window_size":1000000},"cost":{"total_cost_usd":0.85,"total_lines_added":150,"total_lines_removed":30,"total_duration_ms":222000},"workspace":{"current_dir":"C:/Users/dev/my-project"},"worktree":{"branch":"worktree-my-feature","name":"my-feature","path":"C:/path/to/worktree"}}
'@

# ═══════════════════════════════════════════════════════════════
# 情境分派與執行
# ═══════════════════════════════════════════════════════════════

# 定義所有測試情境的對應表
$scenarios = [ordered]@{
    'normal'   = @{
        Label = 'Normal (42%, green)'
        Json  = $JsonNormal
        Env   = @{}
    }
    'warning'  = @{
        Label = 'Warning (75%, yellow)'
        Json  = $JsonWarning
        Env   = @{}
    }
    'danger'   = @{
        Label = 'Danger (92%, red + warning)'
        Json  = $JsonDanger
        Env   = @{}
    }
    'startup'  = @{
        Label = 'Session startup (zero values hidden)'
        Json  = $JsonStartup
        Env   = @{}
    }
    'agent'    = @{
        Label = 'Agent mode (code-reviewer)'
        Json  = $JsonAgent
        Env   = @{}
    }
    'worktree' = @{
        Label = 'Worktree mode (my-feature)'
        Json  = $JsonWorktree
        Env   = @{}
    }
    'ascii'    = @{
        Label = 'ASCII fallback'
        Json  = $JsonNormal
        Env   = @{ 'CLAUDE_STATUSLINE_ASCII' = '1' }
    }
    'nerdfont' = @{
        Label = 'Nerd Font mode'
        Json  = $JsonNormal
        Env   = @{ 'CLAUDE_STATUSLINE_NERDFONT' = '1' }
    }
}

if ($Scenario -eq 'all') {
    # 依序執行所有情境
    foreach ($key in $scenarios.Keys) {
        $s = $scenarios[$key]
        Invoke-TestScenario -Label $s.Label -Json $s.Json -EnvOverrides $s.Env
    }
}
elseif ($scenarios.Contains($Scenario)) {
    # 執行指定的單一情境
    $s = $scenarios[$Scenario]
    Invoke-TestScenario -Label $s.Label -Json $s.Json -EnvOverrides $s.Env
}
else {
    # 無效的情境名稱
    Write-Host "Unknown scenario: $Scenario" -ForegroundColor Red
    Write-Host "Available: $($scenarios.Keys -join ', '), all" -ForegroundColor Yellow
    exit 1
}
