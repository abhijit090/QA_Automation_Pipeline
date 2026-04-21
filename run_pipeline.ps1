# ============================================================
# run_pipeline.ps1 — Local CI/CD equivalent for Windows
# ============================================================
# USAGE (from project root in PowerShell):
#
#   Full run (uses values from .env):
#     .\run_pipeline.ps1
#
#   Override URL / credentials:
#     .\run_pipeline.ps1 -BaseUrl "https://yourapp.com" -Username "user@test.com" -Password "pass123"
#
#   Run a specific script:
#     .\run_pipeline.ps1 -Script "tests/generated/test_abc123.robot"
#
#   Run headless (no browser window):
#     .\run_pipeline.ps1 -Headless
#
#   Generate + open Allure report only (no test run):
#     .\run_pipeline.ps1 -ReportOnly
# ============================================================

param(
    [string]$Script    = "tests/generated",
    [string]$BaseUrl   = "",
    [string]$Username  = "",
    [string]$Password  = "",
    [string]$Browser   = "Chrome",
    [switch]$Headless  = $false,
    [switch]$ReportOnly = $false
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  AI-Powered QA Automation — Local Pipeline" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ── Load .env if credentials not supplied ────────────────────
$EnvFile = Join-Path $Root ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim())
        }
    }
    Write-Host "[OK] Loaded .env" -ForegroundColor Green
} else {
    Write-Host "[WARN] No .env file found — make sure variables are set" -ForegroundColor Yellow
}

# ── Resolve credentials (param > .env > empty) ───────────────
if (-not $BaseUrl)  { $BaseUrl  = $env:TEST_BASE_URL }
if (-not $Username) { $Username = $env:TEST_USERNAME }
if (-not $Password) { $Password = $env:TEST_PASSWORD }
$HeadlessVal = if ($Headless) { "true" } else { "false" }

# ── Activate virtual environment ─────────────────────────────
$Activate = Join-Path $Root ".venv\Scripts\Activate.ps1"
if (Test-Path $Activate) {
    & $Activate
    Write-Host "[OK] Virtual environment activated" -ForegroundColor Green
} else {
    Write-Host "[WARN] .venv not found — using system Python" -ForegroundColor Yellow
}

# ── Report-only mode ─────────────────────────────────────────
if ($ReportOnly) {
    Write-Host "`n[→] Generating Allure report from existing results..." -ForegroundColor Cyan
    allure generate reports/allure-results --output reports/allure-report --clean
    Write-Host "[OK] Report generated → reports/allure-report/index.html" -ForegroundColor Green
    Write-Host "[→] Opening report..." -ForegroundColor Cyan
    allure open reports/allure-report
    exit 0
}

# ── Validate inputs ───────────────────────────────────────────
if (-not $BaseUrl) {
    Write-Host "[ERROR] BASE_URL is not set." -ForegroundColor Red
    Write-Host "        Set TEST_BASE_URL in .env  OR  pass -BaseUrl 'https://...' " -ForegroundColor Red
    exit 1
}
if (-not (Test-Path (Join-Path $Root $Script)) -and -not (Test-Path $Script)) {
    Write-Host "[ERROR] Script/folder not found: $Script" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Script   : $Script"         -ForegroundColor White
Write-Host "  URL      : $BaseUrl"        -ForegroundColor White
Write-Host "  Username : $Username"       -ForegroundColor White
Write-Host "  Browser  : $Browser"        -ForegroundColor White
Write-Host "  Headless : $HeadlessVal"    -ForegroundColor White
Write-Host ""

# ── Clean previous Allure results ────────────────────────────
Write-Host "[→] Clearing previous Allure results..." -ForegroundColor Cyan
if (Test-Path "reports/allure-results") { Remove-Item "reports/allure-results" -Recurse -Force }
New-Item -ItemType Directory -Path "reports/allure-results" -Force | Out-Null
New-Item -ItemType Directory -Path "reports/allure-report"  -Force | Out-Null
New-Item -ItemType Directory -Path "reports/output"         -Force | Out-Null
New-Item -ItemType Directory -Path "reports/screenshots"    -Force | Out-Null
Write-Host "[OK] Directories ready" -ForegroundColor Green

# ── Run Robot Framework ───────────────────────────────────────
Write-Host "`n[→] Running Robot Framework tests..." -ForegroundColor Cyan
Write-Host "--------------------------------------------" -ForegroundColor DarkGray

$RobotArgs = @(
    "--outputdir",  "reports/output",
    "--output",     "output.xml",
    "--log",        "log.html",
    "--report",     "report.html",
    "--loglevel",   "INFO",
    "--listener",   "allure_robotframework;reports/allure-results",
    "--variable",   "BASE_URL:$BaseUrl",
    "--variable",   "USERNAME:$Username",
    "--variable",   "PASSWORD:$Password",
    "--variable",   "HEADLESS:$HeadlessVal",
    "--variable",   "BROWSER:$Browser",
    "--variable",   "SCREENSHOT_DIR:reports/screenshots",
    $Script
)

python -m robot @RobotArgs
$RobotExit = $LASTEXITCODE

Write-Host "--------------------------------------------" -ForegroundColor DarkGray

# ── Generate Allure report ────────────────────────────────────
Write-Host "`n[→] Generating Allure HTML report..." -ForegroundColor Cyan
allure generate reports/allure-results --output reports/allure-report --clean
Write-Host "[OK] Allure report → reports/allure-report/index.html" -ForegroundColor Green

# ── Print summary ─────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RESULTS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RF Report  : reports/output/report.html"    -ForegroundColor White
Write-Host "  RF Log     : reports/output/log.html"       -ForegroundColor White
Write-Host "  Screenshots: reports/screenshots/"          -ForegroundColor White
Write-Host "  Allure     : reports/allure-report/index.html" -ForegroundColor White
Write-Host ""

if ($RobotExit -eq 0) {
    Write-Host "  STATUS: ALL TESTS PASSED" -ForegroundColor Green
} elseif ($RobotExit -eq 1) {
    Write-Host "  STATUS: SOME TESTS FAILED" -ForegroundColor Red
} else {
    Write-Host "  STATUS: EXECUTION ERROR (exit code $RobotExit)" -ForegroundColor Red
}
Write-Host ""

# ── Open Allure report in browser ────────────────────────────
$OpenReport = Read-Host "Open Allure report in browser? (Y/n)"
if ($OpenReport -ne 'n' -and $OpenReport -ne 'N') {
    allure open reports/allure-report
}

exit $RobotExit
