@echo off
chcp 65001 >nul
title DeepSeek 余额桌显 (调试模式)

cd /d "%~dp0"

echo === DeepSeek 余额桌面组件 (调试模式) ===
echo.
echo 当前目录: %cd%
echo PS1 路径: %~dp0deepseek_balance_widget.ps1
echo.

REM 先检查 Python 是否可用
echo [1] 检查 Python 环境 ...
py -3 --version 2>nul
if errorlevel 1 (
    python --version 2>nul
    if errorlevel 1 (
        echo [错误] 找不到 Python！请确认已安装 Python 3.x 并添加到 PATH。
        pause
        exit /b 1
    ) else (
        set "PYCMD=python"
        echo 使用命令: python
    )
) else (
    set "PYCMD=py -3"
    echo 使用命令: py -3
)
echo.

REM 测试 Python 抓取脚本
echo [2] 测试余额抓取 ...
%PYCMD% "%~dp0deepseek_balance_fetch.py"
if errorlevel 1 (
    echo [错误] Python 脚本执行失败，请检查 API key 和网络连接。
    pause
    exit /b 1
)
echo.

REM 启动 PowerShell 组件
echo [3] 启动桌面悬浮窗 ...
echo     右键悬浮窗可调设置，双击关闭。
echo     如果悬浮窗未出现，按 Ctrl+C 退出后查看上方错误信息。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deepseek_balance_widget.ps1"

echo.
echo 组件已退出 (退出码: %errorlevel%)。
pause
