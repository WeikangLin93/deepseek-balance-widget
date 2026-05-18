$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

python -m py_compile deepseek_balance_fetch.py
python -m unittest discover -s tests

$tokens = $null
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Join-Path $repoRoot "deepseek_balance_widget.ps1"),
  [ref]$tokens,
  [ref]$errs
) | Out-Null

if ($errs) {
  $errs | ForEach-Object { Write-Error $_.Message }
  exit 1
}

Write-Host "All checks passed."
