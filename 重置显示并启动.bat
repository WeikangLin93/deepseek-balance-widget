@echo off
chcp 65001 >nul
title 重置 DeepSeek 余额桌显

echo 正在关闭已有组件...
taskkill /f /im powershell.exe /fi "WINDOWTITLE eq DeepSeek 余额桌显" 2>nul

echo 正在删除配置文件...
if exist "%LOCALAPPDATA%\DeepSeekBalanceWidget\widget_config.json" (
    del /f /q "%LOCALAPPDATA%\DeepSeekBalanceWidget\widget_config.json"
    echo 配置文件已删除。
) else (
    echo 未找到配置文件。
)

if exist "%LOCALAPPDATA%\DeepSeekBalanceWidget\last_balance.json" (
    del /f /q "%LOCALAPPDATA%\DeepSeekBalanceWidget\last_balance.json"
    echo 缓存文件已删除。
)

echo.
echo 重置完成。重新运行"启动DeepSeek余额桌显.bat"即可。
pause
