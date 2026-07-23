Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:MainRunspace = $Host.Runspace
[System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $script:MainRunspace

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  public struct MONITORINFO {
    public int cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public uint dwFlags;
  }

  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
  [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
}
"@

# 错误日志
$logDir = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "DeepSeekBalanceWidget"
if (-not (Test-Path $logDir)) { [void](New-Item -ItemType Directory -Path $logDir -Force) }
$logPath = Join-Path $logDir "error.log"
function Write-Log($msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
  Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}
Write-Log "=== Widget started ==="
Write-Log "PSScriptRoot: $PSScriptRoot"

function Get-AppDataDir {
  $base = [Environment]::GetFolderPath("LocalApplicationData")
  if (-not $base) { $base = [Environment]::GetFolderPath("ApplicationData") }
  if (-not $base) { $base = $PSScriptRoot }
  $dir = Join-Path $base "DeepSeekBalanceWidget"
  if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  return $dir
}

$appDataDir = Get-AppDataDir
$configPath = Join-Path $appDataDir "widget_config.json"
$legacyConfigPath = Join-Path $PSScriptRoot "widget_config.json"
$defaultConfig = @{
  opacity = 0.90
  layer_mode = "topmost"
  game_mode_enabled = $true
  manual_visibility = "none"
}

function Merge-Config($base, $incoming) {
  $m = @{}
  foreach ($k in $base.Keys) { $m[$k] = $base[$k] }
  if ($incoming) {
    foreach ($p in $incoming.PSObject.Properties.Name) {
      $m[$p] = $incoming.$p
    }
  }
  return $m
}

function Load-Config {
  if ((-not (Test-Path $configPath)) -and (Test-Path $legacyConfigPath)) {
    try { Copy-Item -Path $legacyConfigPath -Destination $configPath -Force } catch {}
  }
  if (Test-Path $configPath) {
    try {
      $obj = Get-Content $configPath -Raw | ConvertFrom-Json
      $cfg = Merge-Config $defaultConfig $obj
      return @{
        opacity = [double]$cfg.opacity
        layer_mode = [string]$cfg.layer_mode
        game_mode_enabled = [bool]$cfg.game_mode_enabled
        manual_visibility = [string]$cfg.manual_visibility
      }
    } catch {}
  }
  return $defaultConfig.Clone()
}

function Save-Config($cfg) {
  $cfg | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8
}

function Get-TaskbarLikeColor {
  try {
    $v = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name SystemUsesLightTheme -ErrorAction Stop
    if ([int]$v.SystemUsesLightTheme -eq 0) {
      return [System.Drawing.Color]::FromArgb(32,32,32)
    } else {
      return [System.Drawing.Color]::FromArgb(242,242,242)
    }
  } catch {
    return [System.Drawing.Color]::FromArgb(32,32,32)
  }
}

$script:cfg = Load-Config
$script:balance = @{
  ok = $false
  from_cache = $false
  error_kind = ""
  total_balance = 0.0
  granted_balance = 0.0
  topped_up_balance = 0.0
  currency = "CNY"
  is_available = $false
  error = ""
  ts = 0
}
$script:hovering = $false
$script:lastAutoFullscreen = $false
$script:pendingRestoreAt = $null
$script:refreshJob = $null
$script:nextRefreshAt = Get-Date
$script:isRefreshing = $false
$script:telemetryJob = $null

function Start-LaunchTelemetry {
  if ($env:DEEPSEEK_BALANCE_WIDGET_DISABLE_TELEMETRY -eq "1") { return }
  if ($script:telemetryJob -and $script:telemetryJob.State -eq "Running") { return }

  $telemetryUrl = "https://hits.sh/github.com/WeikangLin93/deepseek-balance-widget/app-launch.svg?label=launches"
  $script:telemetryJob = Start-Job -ArgumentList $telemetryUrl -ScriptBlock {
    param($url)
    try {
      Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 | Out-Null
    } catch {}
  }
}

function Set-LayerMode([string]$mode) {
  if ($mode -eq "topmost") {
    $form.TopMost = $true
  } else {
    $form.TopMost = $false
  }
  $script:cfg.layer_mode = $mode
  Save-Config $script:cfg
}

function Set-OpacityValue([double]$val) {
  $v = [Math]::Min(1.0, [Math]::Max(0.20, $val))
  $form.Opacity = $v
  $script:cfg.opacity = $v
  Save-Config $script:cfg
}

function Start-BalanceRefresh {
  if ($script:refreshJob -and $script:refreshJob.State -eq "Running") { return }
  if ($script:refreshJob) {
    try { Remove-Job -Job $script:refreshJob -Force -ErrorAction SilentlyContinue } catch {}
    $script:refreshJob = $null
  }

  $fetchScript = Join-Path $PSScriptRoot "deepseek_balance_fetch.py"
  Write-Log "Start-BalanceRefresh: fetchScript=$fetchScript, exists=$(Test-Path $fetchScript)"
  $script:isRefreshing = $true

  $script:refreshJob = Start-Job -ArgumentList $fetchScript -ScriptBlock {
    param($scriptPath)
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
      & py -3 $scriptPath 2>$null
    } else {
      & python $scriptPath 2>$null
    }
  }
}

function Complete-BalanceRefresh {
  if (-not $script:refreshJob) { return }
  if ($script:refreshJob.State -eq "Running") { return }

  try {
    $json = Receive-Job -Job $script:refreshJob -ErrorAction Stop
    Write-Log "Complete: received json=$($json -ne $null), length=$(if($json){$json.Length}else{0})"
    if (-not $json) { throw "Python 没有返回数据" }
    $obj = ($json | Select-Object -Last 1) | ConvertFrom-Json
    if ($obj) { $script:balance = $obj }
  } catch {
    $script:balance.ok = $false
    $script:balance.error = $_.Exception.Message
    $script:balance.error_kind = "widget"
  } finally {
    try { Remove-Job -Job $script:refreshJob -Force -ErrorAction SilentlyContinue } catch {}
    $script:refreshJob = $null
    $script:isRefreshing = $false
    $script:nextRefreshAt = (Get-Date).AddSeconds(60)
  }

  Update-NotifyText
  $form.Invalidate()
}

function Update-NotifyText {
  $status = if ($script:isRefreshing) { "刷新中" } elseif ($script:balance.ok) { if ($script:balance.from_cache) { "缓存" } else { "正常" } } else { "异常" }
  $gm = Get-GameModeText
  $bal = [math]::Round($script:balance.total_balance, 2)
  $notify.Text = "DeepSeek [${gm}/${status}] 余额: ¥${bal}"
}

function Get-GameModeText {
  if (-not $script:cfg.game_mode_enabled) { return "OFF" }
  switch ($script:cfg.manual_visibility) {
    "force_hide" { return "MANUAL-HIDE" }
    "force_show" { return "MANUAL-SHOW" }
    default { return "AUTO" }
  }
}

function Is-ForegroundFullscreen {
  try {
    $hwnd = [Win32]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return $false }

    $rect = New-Object Win32+RECT
    if (-not [Win32]::GetWindowRect($hwnd, [ref]$rect)) { return $false }

    $hmon = [Win32]::MonitorFromWindow($hwnd, 2)
    if ($hmon -eq [IntPtr]::Zero) { return $false }

    $mi = New-Object Win32+MONITORINFO
    $mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type]"Win32+MONITORINFO")
    if (-not [Win32]::GetMonitorInfo($hmon, [ref]$mi)) { return $false }

    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    $mw = $mi.rcMonitor.Right - $mi.rcMonitor.Left
    $mh = $mi.rcMonitor.Bottom - $mi.rcMonitor.Top

    $sizeMatch = ($w -ge ($mw - 8) -and $h -ge ($mh - 8))
    $posMatch = ([Math]::Abs($rect.Left - $mi.rcMonitor.Left) -le 8 -and [Math]::Abs($rect.Top - $mi.rcMonitor.Top) -le 8)
    return ($sizeMatch -and $posMatch)
  } catch {
    return $false
  }
}

function Apply-VisibilityPolicy {
  $now = Get-Date

  if (-not $script:cfg.game_mode_enabled) {
    $form.Visible = $true
    return
  }

  if ($script:cfg.manual_visibility -eq "force_hide") {
    $form.Visible = $false
    return
  }
  if ($script:cfg.manual_visibility -eq "force_show") {
    $form.Visible = $true
    return
  }

  $isFs = Is-ForegroundFullscreen
  if ($isFs) {
    $script:lastAutoFullscreen = $true
    $script:pendingRestoreAt = $null
    $form.Visible = $false
    return
  }

  if ($script:lastAutoFullscreen) {
    if (-not $script:pendingRestoreAt) {
      $script:pendingRestoreAt = $now.AddSeconds(2)
      return
    }
    if ($now -lt $script:pendingRestoreAt) {
      return
    }
    $script:lastAutoFullscreen = $false
    $script:pendingRestoreAt = $null
    $form.Visible = $true
    return
  }

  $form.Visible = $true
}

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Size = New-Object System.Drawing.Size(210, 132)
$form.BackColor = Get-TaskbarLikeColor
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.Opacity = [Math]::Min(1.0, [Math]::Max(0.20, [double]$script:cfg.opacity))

$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($wa.Right - $form.Width - 16), ($wa.Bottom - $form.Height - 16))

if ($script:cfg.layer_mode -eq "normal") { $form.TopMost = $false }

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.Visible = $true
$notify.Text = "DeepSeek 余额"

$menu = New-Object System.Windows.Forms.ContextMenuStrip

# Opacity submenu
$opacityItem = New-Object System.Windows.Forms.ToolStripMenuItem
$opacityItem.Text = "透明度"

$op60 = New-Object System.Windows.Forms.ToolStripMenuItem
$op60.Text = "60%"
$op60.Add_Click({ Set-OpacityValue 0.60 })

$op70 = New-Object System.Windows.Forms.ToolStripMenuItem
$op70.Text = "70%"
$op70.Add_Click({ Set-OpacityValue 0.70 })

$op80 = New-Object System.Windows.Forms.ToolStripMenuItem
$op80.Text = "80%"
$op80.Add_Click({ Set-OpacityValue 0.80 })

$op90 = New-Object System.Windows.Forms.ToolStripMenuItem
$op90.Text = "90%"
$op90.Add_Click({ Set-OpacityValue 0.90 })

$op100 = New-Object System.Windows.Forms.ToolStripMenuItem
$op100.Text = "100%"
$op100.Add_Click({ Set-OpacityValue 1.0 })

[void]$opacityItem.DropDownItems.Add($op60)
[void]$opacityItem.DropDownItems.Add($op70)
[void]$opacityItem.DropDownItems.Add($op80)
[void]$opacityItem.DropDownItems.Add($op90)
[void]$opacityItem.DropDownItems.Add($op100)

# Layer submenu
$layerItem = New-Object System.Windows.Forms.ToolStripMenuItem
$layerItem.Text = "图层"

$layerTop = New-Object System.Windows.Forms.ToolStripMenuItem
$layerTop.Text = "始终置顶"
$layerTop.Add_Click({ Set-LayerMode "topmost" })

$layerNormal = New-Object System.Windows.Forms.ToolStripMenuItem
$layerNormal.Text = "普通层级"
$layerNormal.Add_Click({ Set-LayerMode "normal" })

[void]$layerItem.DropDownItems.Add($layerTop)
[void]$layerItem.DropDownItems.Add($layerNormal)

# Game mode submenu
$gameItem = New-Object System.Windows.Forms.ToolStripMenuItem
$gameItem.Text = "游戏模式"

$gameAuto = New-Object System.Windows.Forms.ToolStripMenuItem
$gameAuto.Text = "自动(AUTO)"
$gameAuto.Add_Click({
  $script:cfg.game_mode_enabled = $true
  $script:cfg.manual_visibility = "none"
  Save-Config $script:cfg
  Apply-VisibilityPolicy
})

$gameForceShow = New-Object System.Windows.Forms.ToolStripMenuItem
$gameForceShow.Text = "强制显示"
$gameForceShow.Add_Click({
  $script:cfg.game_mode_enabled = $true
  $script:cfg.manual_visibility = "force_show"
  Save-Config $script:cfg
  Apply-VisibilityPolicy
})

$gameForceHide = New-Object System.Windows.Forms.ToolStripMenuItem
$gameForceHide.Text = "强制隐藏"
$gameForceHide.Add_Click({
  $script:cfg.game_mode_enabled = $true
  $script:cfg.manual_visibility = "force_hide"
  Save-Config $script:cfg
  Apply-VisibilityPolicy
})

$gameOff = New-Object System.Windows.Forms.ToolStripMenuItem
$gameOff.Text = "关闭游戏模式"
$gameOff.Add_Click({
  $script:cfg.game_mode_enabled = $false
  Save-Config $script:cfg
  Apply-VisibilityPolicy
})

[void]$gameItem.DropDownItems.Add($gameAuto)
[void]$gameItem.DropDownItems.Add($gameForceShow)
[void]$gameItem.DropDownItems.Add($gameForceHide)
[void]$gameItem.DropDownItems.Add($gameOff)

$refreshNow = New-Object System.Windows.Forms.ToolStripMenuItem
$refreshNow.Text = "立即刷新"
$refreshNow.Add_Click({ Start-BalanceRefresh })

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = "关闭"
$exitItem.Add_Click({ $form.Close() })

[void]$menu.Items.Add($opacityItem)
[void]$menu.Items.Add($layerItem)
[void]$menu.Items.Add($gameItem)
[void]$menu.Items.Add($refreshNow)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($exitItem)

$notify.ContextMenuStrip = $menu

# Right-click on form also shows menu
$form.Add_MouseUp({
  if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
    $menu.Show($form, $_.Location)
  }
})

# Double-click to close
$form.Add_MouseDoubleClick({ $form.Close() })

# Mouse enter/leave for hover hint
$form.Add_MouseEnter({ $script:hovering = $true; $form.Invalidate() })
$form.Add_MouseLeave({ $script:hovering = $false; $form.Invalidate() })

$form.Add_Paint({
  $g = $_.Graphics
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

  $isDark = ($form.BackColor.R + $form.BackColor.G + $form.BackColor.B) -lt 384

  if ($isDark) {
    $textPrimary = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $textSecondary = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 180, 180))
    $textMuted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 140, 140))
    $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(84, 184, 255))
    $okBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 200, 120))
    $cacheBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 200, 60))
    $badBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 80, 80))
  } else {
    $textPrimary = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(32, 32, 32))
    $textSecondary = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(100, 100, 100))
    $textMuted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 160, 160))
    $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 212))
    $okBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 150, 50))
    $cacheBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 140, 0))
    $badBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 40, 40))
  }

  $fontTitle = New-Object System.Drawing.Font("Microsoft YaHei", 9, [System.Drawing.FontStyle]::Bold)
  $fontBalance = New-Object System.Drawing.Font("Microsoft YaHei", 22, [System.Drawing.FontStyle]::Bold)
  $fontSmall = New-Object System.Drawing.Font("Microsoft YaHei", 8)
  $fontTiny = New-Object System.Drawing.Font("Microsoft YaHei", 7)

  # Title
  $g.DrawString("DeepSeek 余额", $fontTitle, $textPrimary, 10, 8)

  # Status indicator
  $statusText = "异常"
  $statusBrush = $badBrush
  if ($script:isRefreshing) {
    $statusText = "刷新中"
    $statusBrush = $accentBrush
  } elseif ($script:balance.ok) {
    if ($script:balance.from_cache) {
      $statusText = "缓存"
      $statusBrush = $cacheBrush
    } else {
      $statusText = "正常"
      $statusBrush = $okBrush
    }
  }

  $gmText = Get-GameModeText
  $g.DrawString("状态: ${statusText}", $fontSmall, $statusBrush, 135, 10)
  $g.DrawString($gmText, $fontSmall, $textMuted, 135, 26)

  # Balance big number
  $balStr = "¥" + [math]::Round($script:balance.total_balance, 2).ToString("F2")
  if (-not $script:balance.ok) { $balStr = "¥ --.--" }
  $g.DrawString($balStr, $fontBalance, $textPrimary, 10, 34)

  # Sub balances
  $grantedStr = "赠送 ¥" + [math]::Round($script:balance.granted_balance, 2).ToString("F2")
  $toppedStr = "充值 ¥" + [math]::Round($script:balance.topped_up_balance, 2).ToString("F2")
  $g.DrawString("${grantedStr}  ${toppedStr}", $fontSmall, $textSecondary, 12, 70)

  # Bottom line
  if ($script:hovering) {
    $g.DrawString("右键调设置 / 双击关闭", $fontTiny, $textMuted, 10, 112)
  } elseif ($script:isRefreshing) {
    $g.DrawString("正在后台刷新...", $fontTiny, $accentBrush, 10, 112)
  } else {
    if ($script:balance.ok -and -not $script:balance.from_cache) {
      $tsText = if ($script:balance.ts) { ([DateTimeOffset]::FromUnixTimeSeconds([int64]$script:balance.ts).ToLocalTime().ToString("HH:mm:ss")) } else { "--:--:--" }
      $g.DrawString(("刷新于 " + $tsText), $fontTiny, $textMuted, 10, 112)
    } elseif ($script:balance.from_cache) {
      $g.DrawString("接口异常 (使用缓存)", $fontTiny, $cacheBrush, 10, 112)
    } else {
      $g.DrawString("无法获取余额", $fontTiny, $badBrush, 10, 112)
    }
  }

  $textPrimary.Dispose(); $textSecondary.Dispose(); $textMuted.Dispose(); $accentBrush.Dispose(); $okBrush.Dispose(); $cacheBrush.Dispose(); $badBrush.Dispose(); $fontTitle.Dispose(); $fontBalance.Dispose(); $fontSmall.Dispose(); $fontTiny.Dispose()
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
  Apply-VisibilityPolicy
  Complete-BalanceRefresh
  if ((Get-Date) -ge $script:nextRefreshAt) { Start-BalanceRefresh }
})
$timer.Start()

$form.Add_FormClosing({
  if ($script:refreshJob) {
    try { Remove-Job -Job $script:refreshJob -Force -ErrorAction SilentlyContinue } catch {}
    $script:refreshJob = $null
  }
  if ($script:telemetryJob) {
    try { Remove-Job -Job $script:telemetryJob -Force -ErrorAction SilentlyContinue } catch {}
    $script:telemetryJob = $null
  }
  $notify.Visible = $false
  $notify.Dispose()
})

Start-LaunchTelemetry
Start-BalanceRefresh
Start-Sleep -Milliseconds 800
Apply-VisibilityPolicy
Update-NotifyText
Write-Log "Entering message loop, Visible=$($form.Visible), Location=$($form.Location)"
[System.Windows.Forms.Application]::Run($form)
