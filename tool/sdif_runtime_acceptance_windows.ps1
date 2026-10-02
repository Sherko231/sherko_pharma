param(
    [int]$Port = 3000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$PinnedCommit = '9f8f69519e4806d9e0e7021f403bdcb52ed77cc0'
$ExpectedSnapshotSha256 = '9e5498675acca91097899e66181a27b056cb2026f0d903e686da9cf5c62c3206'

$repoRoot = Split-Path -Parent $PSScriptRoot
$workingRoot = Join-Path $repoRoot 'sdif_working_dir'
$sdifDir = Join-Path $workingRoot 'sdif-pinned'
$dbPath = Join-Path $sdifDir 'db\interactions.db'
$exePath = Join-Path $sdifDir 'target\release\sdif.exe'
$packageConfig = Join-Path $repoRoot '.dart_tool\package_config.json'
$stdoutLog = Join-Path $workingRoot 'sdif_runtime_server.out.log'
$stderrLog = Join-Path $workingRoot 'sdif_runtime_server.err.log'

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name"
    }
}

Require-Command 'git'
Require-Command 'cargo'
Require-Command 'flutter'
Require-Command 'dart'

if (-not (Test-Path $sdifDir -PathType Container)) {
    throw "Pinned SDIF checkout is missing: $sdifDir. Run .\tool\sdif_bootstrap_windows.ps1 first."
}
if (-not (Test-Path $dbPath -PathType Leaf)) {
    throw "Pinned SDIF database is missing: $dbPath. Run .\tool\sdif_bootstrap_windows.ps1 first."
}

$head = (& git -C $sdifDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $PinnedCommit) {
    throw "SDIF checkout mismatch. Expected $PinnedCommit, got $head"
}

$dirtyTracked = (& git -C $sdifDir status --porcelain --untracked-files=no) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect pinned SDIF checkout status.'
}
if (-not [string]::IsNullOrWhiteSpace($dirtyTracked)) {
    throw 'Pinned SDIF checkout has tracked modifications. Restore it before live acceptance.'
}

$actualSnapshotSha256 = (Get-FileHash -Algorithm SHA256 $dbPath).Hash.ToLowerInvariant()
if ($actualSnapshotSha256 -ne $ExpectedSnapshotSha256) {
    throw "SDIF snapshot hash mismatch. Expected $ExpectedSnapshotSha256, got $actualSnapshotSha256"
}

Push-Location $sdifDir
try {
    & cargo build --release
    if ($LASTEXITCODE -ne 0) {
        throw "Pinned SDIF release build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $exePath -PathType Leaf)) {
    throw "Pinned SDIF release executable was not produced: $exePath"
}

if (-not (Test-Path $packageConfig -PathType Leaf)) {
    Push-Location $repoRoot
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

Remove-Item $stdoutLog -ErrorAction SilentlyContinue
Remove-Item $stderrLog -ErrorAction SilentlyContinue

$server = $null
try {
    $server = Start-Process `
        -FilePath $exePath `
        -ArgumentList @('serve', '--epha', '--port', $Port.ToString()) `
        -WorkingDirectory $sdifDir `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru `
        -WindowStyle Hidden

    $ready = $false
    $readyUri = "http://127.0.0.1:$Port/api/search-drugs?atc=J01CA04"
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        Start-Sleep -Milliseconds 200
        if ($server.HasExited) {
            $serverError = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
            throw "SDIF server exited before readiness. $serverError"
        }
        try {
            $probe = Invoke-RestMethod -Uri $readyUri -Method Get -TimeoutSec 2
            if ($probe -is [System.Array] -and $probe.Count -ge 1) {
                $ready = $true
                break
            }
        }
        catch {
            # Retry until the bounded readiness deadline below.
        }
    }

    if (-not $ready) {
        throw "SDIF server did not become ready at http://127.0.0.1:$Port/"
    }

    Push-Location $repoRoot
    try {
        & dart run tool/sdif_live_acceptance.dart --base-url "http://127.0.0.1:$Port/"
        if ($LASTEXITCODE -ne 0) {
            throw "Live SDIF acceptance failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($null -ne $server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
        $server.WaitForExit()
    }
}
