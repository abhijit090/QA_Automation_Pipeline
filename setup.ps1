param()
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Show-Header($t) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
}
function OK($t)   { Write-Host "  [OK]  $t" -ForegroundColor Green  }
function WARN($t) { Write-Host "  [!!]  $t" -ForegroundColor Yellow }
function FAIL($t) { Write-Host "  [XX]  $t" -ForegroundColor Red    }

Show-Header "AI-Powered QA Automation -- Setup"

# STEP 1: Prerequisites
Show-Header "STEP 1 -- Checking Prerequisites"

$pyOk = $false
try { $v = python --version 2>&1; OK "Python        : $v"; $pyOk = $true }
catch { FAIL "Python not found. Install: https://www.python.org/downloads/" }
if (-not $pyOk) { exit 1 }

try { $v = node --version 2>&1; OK "Node.js       : $v" }
catch { WARN "Node.js not found. Install: https://nodejs.org/" }

try { $v = npm --version 2>&1; OK "npm           : $v" }
catch { WARN "npm not found" }

$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
)
$cfound = $false
foreach ($p in $chromePaths) {
    if (Test-Path $p) {
        $v = (Get-Item $p).VersionInfo.FileVersion
        OK "Chrome        : $v"
        $cfound = $true
        break
    }
}
if (-not $cfound) { WARN "Chrome not found. Install: https://www.google.com/chrome/" }

# STEP 2: Virtual Environment
Show-Header "STEP 2 -- Virtual Environment"
if (Test-Path ".venv") {
    OK ".venv already exists"
} else {
    Write-Host "  Creating .venv ..." -ForegroundColor White
    python -m venv .venv
    OK ".venv created"
}

# STEP 3: Activate
Show-Header "STEP 3 -- Activate .venv"
& .\.venv\Scripts\Activate.ps1
OK "Virtual environment activated"

# STEP 4: Upgrade pip
Show-Header "STEP 4 -- Upgrade pip"
python -m pip install --upgrade pip --quiet
$v = pip --version
OK "pip: $v"

# STEP 5: Install packages
Show-Header "STEP 5 -- Install Python Packages"
Write-Host ""
pip install -r requirements.txt
Write-Host ""
OK "All Python packages installed"

# STEP 6: Allure CLI
Show-Header "STEP 6 -- Allure CLI"
$aVer = allure --version 2>&1
if ($LASTEXITCODE -eq 0) {
    OK "Allure CLI already installed: $aVer"
} else {
    Write-Host "  Installing allure-commandline ..." -ForegroundColor White
    npm install -g allure-commandline
    $aVer = allure --version 2>&1
    OK "Allure CLI installed: $aVer"
}

# STEP 7: .env file
Show-Header "STEP 7 -- Environment File (.env)"
if (Test-Path ".env") {
    OK ".env already exists"
} else {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        WARN ".env created from .env.example -- fill in ANTHROPIC_API_KEY!"
    } else {
        "ANTHROPIC_API_KEY=sk-ant-api03-your_key_here`nAI_MODEL=claude-sonnet-4-6`nJIRA_BASE_URL=https://yourcompany.atlassian.net`nJIRA_USERNAME=your.email@company.com`nJIRA_API_TOKEN=your_jira_api_token_here`nJIRA_PROJECT_KEY=QA`nJIRA_BOARD_ID=1234`nSECRET_KEY=change-me`nDEBUG=false`nPORT=5000`nBROWSER=Chrome" | Out-File ".env" -Encoding utf8
        WARN ".env created with placeholders -- fill in ANTHROPIC_API_KEY!"
    }
}

# STEP 8: Verify
Show-Header "STEP 8 -- Verification"

$allOk = $true
$verifyItems = @(
    @("Python",                "python --version"),
    @("Flask",                 "python -c `"import flask; print('OK')`""),
    @("Anthropic Claude SDK",  "python -c `"import anthropic; print(anthropic.__version__)`""),
    @("Robot Framework",       "python -m robot --version"),
    @("SeleniumLibrary",       "python -c `"import SeleniumLibrary; print(SeleniumLibrary.__version__)`""),
    @("Selenium",              "python -c `"import selenium; print(selenium.__version__)`""),
    @("Allure RF Listener",    "python -c `"import allure_robotframework; print('OK')`""),
    @("python-dotenv",         "python -c `"import dotenv; print('OK')`""),
    @("requests",              "python -c `"import requests; print(requests.__version__)`""),
    @("Node.js",               "node --version"),
    @("Allure CLI",            "allure --version")
)

foreach ($item in $verifyItems) {
    $label = $item[0]
    $cmd   = $item[1]
    try {
        $out = (Invoke-Expression $cmd 2>&1) | Select-Object -First 1
        if ("$out" -match "DeprecationWarning") { $out = "OK" }
        Write-Host ("  [OK]  {0,-30} {1}" -f $label, $out) -ForegroundColor Green
    } catch {
        Write-Host ("  [XX]  {0,-30} FAILED" -f $label) -ForegroundColor Red
        $allOk = $false
    }
}

# STEP 9: Summary
Show-Header "SETUP COMPLETE"
if ($allOk) {
    Write-Host "  All tools verified successfully." -ForegroundColor Green
} else {
    Write-Host "  Some checks failed -- review errors above." -ForegroundColor Red
}

Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  [1] Add your API key:   notepad .env" -ForegroundColor White
Write-Host "  [2] Start Flask UI:     python app.py    then open http://localhost:5000" -ForegroundColor White
Write-Host "  [3] Run pipeline:       .\run_pipeline.ps1" -ForegroundColor White
Write-Host "  [4] Run one script:     .\run_pipeline.ps1 -Script tests\generated\test_xyz.robot" -ForegroundColor White
Write-Host "  [5] Run headless:       .\run_pipeline.ps1 -Headless" -ForegroundColor White
Write-Host "  [6] Push to GitHub:     git add . ; git commit -m 'run' ; git push origin main" -ForegroundColor White
Write-Host ""