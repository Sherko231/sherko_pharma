$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$bootstrap = Join-Path $PSScriptRoot 'sdif_bootstrap.py'

$python = Get-Command python.exe -ErrorAction SilentlyContinue
if ($null -ne $python) {
    & $python.Source $bootstrap @args
    exit $LASTEXITCODE
}

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if ($null -ne $py) {
    & $py.Source -3 $bootstrap @args
    exit $LASTEXITCODE
}

Write-Error 'Python 3 was not found. Install Python 3.11+ and ensure python.exe or py.exe is available on PATH.'
exit 2
