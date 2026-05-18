# DeepSeek 余额桌显 - 诊断版本
# 右键此文件 -> "使用 PowerShell 运行"
# 或在 PowerShell 中执行: .\diagnose.ps1

$ErrorActionPreference = "Stop"
$logFile = "$env:LOCALAPPDATA\DeepSeekBalanceWidget\diagnose.log"
if (-not (Test-Path (Split-Path $logFile))) { New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null }

function log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Write-Host $line
    Add-Content $logFile -Value $line -Encoding UTF8
}

log "=== 诊断开始 ==="
log "PSScriptRoot: $PSScriptRoot"
log "PowerShell版本: $($PSVersionTable.PSVersion)"
log "当前目录: $(Get-Location)"

# 1. 检查 WinForms
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    log "WinForms DLL 加载成功"
} catch {
    log "WinForms DLL 加载失败: $_"
    Read-Host "按回车退出"
    exit 1
}

# 2. 检查 Python
$fetchScript = Join-Path $PSScriptRoot "deepseek_balance_fetch.py"
log "抓取脚本路径: $fetchScript"
log "脚本存在: $(Test-Path $fetchScript)"

try {
    $result = & python $fetchScript 2>&1
    log "Python 执行成功"
    log "输出前100字符: $($result.Substring(0, [Math]::Min(100, $result.Length)))"
} catch {
    log "Python 执行失败: $_"
    try {
        $result = & py -3 $fetchScript 2>&1
        log "py -3 执行成功"
    } catch {
        log "py -3 也失败了: $_"
    }
}

# 3. 尝试创建最小窗口
log "尝试创建测试窗口..."
try {
    $testForm = New-Object System.Windows.Forms.Form
    $testForm.Size = New-Object System.Drawing.Size(200, 100)
    $testForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $testForm.Text = "诊断窗口 - 5秒后自动关闭"
    $testForm.TopMost = $true
    
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "如果看到此窗口，说明 WinForms 正常工作"
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(10, 20)
    $testForm.Controls.Add($label)
    
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 5000
    $timer.Add_Tick({ $testForm.Close() })
    $timer.Start()
    
    log "显示测试窗口..."
    $testForm.ShowDialog() | Out-Null
    log "测试窗口已关闭 - WinForms 正常"
} catch {
    log "WinForms 窗口创建失败: $_"
}

log "=== 诊断完成 ==="
log "日志文件: $logFile"
Write-Host ""
Read-Host "按回车退出"
