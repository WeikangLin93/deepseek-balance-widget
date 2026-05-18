Set objShell = CreateObject("WScript.Shell")
strPath = objShell.CurrentDirectory & "\deepseek_balance_widget.ps1"
objShell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strPath & """", 0, False
