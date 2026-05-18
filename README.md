# DeepSeek Balance Widget / DeepSeek 余额桌面小组件

A **Windows desktop floating widget** for monitoring DeepSeek API balance.  
一个用于 **Windows 桌面右下角悬浮显示** DeepSeek API 余额的小工具。

## Preview / 界面预览

| Light mode / 浅色模式 | Dark mode / 深色模式 |
| --- | --- |
| ¥15.81 total balance | ¥15.81 total balance |

The widget shows total balance in CNY (¥), with granted and topped-up breakdowns.  
小组件以人民币（¥）显示总余额，并分列赠送余额和充值余额。

---

## Features / 功能特点

- Displays total, granted, and topped-up DeepSeek balance in CNY  
  显示 DeepSeek 总余额、赠送余额和充值余额（人民币）
- Auto-refreshes every 60 seconds  
  每 60 秒自动刷新
- Background refresh keeps the widget responsive  
  后台刷新，不因网络请求卡住悬浮窗
- Adaptive light/dark theme following Windows system setting  
  自动跟随系统明暗主题颜色
- Adjustable opacity (60%–100%)  
  支持透明度调节（60%–100%）
- Layer mode switch (always-on-top / normal)  
  图层切换（始终置顶 / 普通层级）
- Game mode (auto full-screen detection + manual force show/hide)  
  游戏模式（自动检测全屏 + 手动强制显示/隐藏）
- Network fallback to local cache on API failure  
  网络异常时使用本地缓存数据显示
- Reads API key from `~/.deepseek/config.toml` — no extra config needed  
  自动读取 `~/.deepseek/config.toml` 中的 API key，无需额外配置
- Stores runtime config/cache under `%LOCALAPPDATA%\DeepSeekBalanceWidget`  
  运行文件保存到 AppData，项目目录保持干净

---

## Project Structure / 项目结构

- `deepseek_balance_widget.ps1` — PowerShell desktop widget UI / 桌面悬浮窗主程序
- `deepseek_balance_fetch.py` — Fetches DeepSeek balance and returns JSON / 请求余额接口返回 JSON
- `run_hidden.vbs` — Silent launcher (double-click to start) / 静默启动入口
- `启动DeepSeek余额桌显.bat` — One-click launcher / 一键启动
- `重置显示并启动.bat` — Reset config and restart / 重置配置并重新启动
- `tests/` — Lightweight tests for the Python fetcher / Python 抓取逻辑的轻量测试
- `scripts/` — CI check and release packaging / 检查与发布打包脚本

---

## Requirements / 依赖

- Windows 10/11
- PowerShell 5+
- Python 3.8+

---

## How to Use / 使用方法

### 中文
1. 确保 `~/.deepseek/config.toml` 中配置了有效的 DeepSeek API key，或设置环境变量 `DEEPSEEK_API_KEY`。
2. 双击 `启动DeepSeek余额桌显.bat` 或 `run_hidden.vbs`。
3. 右下角出现悬浮窗后，可右键调整透明度、图层与游戏模式。
4. 双击悬浮窗可关闭。

如果出现显示异常，可运行 `重置显示并启动.bat` 清除配置和缓存后重新启动。

### English
1. Make sure your DeepSeek API key is in `~/.deepseek/config.toml`, or set the `DEEPSEEK_API_KEY` environment variable.
2. Double-click `启动DeepSeek余额桌显.bat` or `run_hidden.vbs`.
3. Right-click the widget to change opacity, layer mode, and game mode.
4. Double-click the widget to close it.

If the widget doesn't display correctly, run `重置显示并启动.bat` to reset config and cache, then restart.

---

## API / 接口说明

Uses the DeepSeek platform balance endpoint / 调用 DeepSeek 平台余额接口：

```
GET https://api.deepseek.com/user/balance
Authorization: Bearer sk-...
```

Response example / 返回示例：

```json
{
  "is_available": true,
  "balance_infos": [
    {
      "currency": "CNY",
      "total_balance": "16.03",
      "granted_balance": "0.00",
      "topped_up_balance": "16.03"
    }
  ]
}
```

---

## Development / 开发

Run checks / 运行检查：

```powershell
.\scripts\check.ps1
```

Build portable zip / 构建便携 zip 包：

```powershell
.\scripts\build_release.ps1
```

To bundle the Python script as a standalone exe:

```powershell
.\scripts\build_release.ps1 -InstallPyInstaller
```

CI runs `scripts/check.ps1` on every push and PR. Pushing a `v*` tag triggers automatic release to GitHub Releases.

CI 在每次 push/PR 时运行检查。推送 `v*` tag 会自动构建 zip 并发布到 GitHub Releases。

---

## License

MIT
