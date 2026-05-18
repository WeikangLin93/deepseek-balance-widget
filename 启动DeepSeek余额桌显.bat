@echo off
cd /d "%~dp0"
start "" /B powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0deepseek_balance_widget.ps1"
