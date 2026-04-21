"""
config.py
Central configuration for the AI-Powered QA Automation System.
Reads all settings from environment variables / .env file.
"""
import os
from dotenv import load_dotenv

load_dotenv()

# ─── Anthropic / AI ──────────────────────────────────────────
ANTHROPIC_API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
# Accept both AI_MODEL and CLAUDE_MODEL (either name works in .env)
AI_MODEL: str = os.getenv("AI_MODEL") or os.getenv("CLAUDE_MODEL") or "claude-sonnet-4-6"

# ─── Jira ────────────────────────────────────────────────────
JIRA_BASE_URL: str = os.getenv("JIRA_BASE_URL", "")
JIRA_USERNAME: str = os.getenv("JIRA_USERNAME", "")
JIRA_API_TOKEN: str = os.getenv("JIRA_API_TOKEN", "")
JIRA_PROJECT_KEY: str = os.getenv("JIRA_PROJECT_KEY", "")
JIRA_BOARD_ID: str = os.getenv("JIRA_BOARD_ID", "")
JIRA_ENABLED: bool = bool(JIRA_BASE_URL and JIRA_API_TOKEN)

# ─── Flask ───────────────────────────────────────────────────
SECRET_KEY: str = os.getenv("SECRET_KEY", "qa-automation-2024-secret")
DEBUG: bool = os.getenv("DEBUG", "false").lower() == "true"
PORT: int = int(os.getenv("PORT", "5000"))

# ─── Robot Framework paths ───────────────────────────────────
_BASE = os.path.dirname(os.path.abspath(__file__))

RF_OUTPUT_DIR: str = os.path.join(_BASE, "reports", "output")
RF_ALLURE_RESULTS: str = os.path.join(_BASE, "reports", "allure-results")
RF_ALLURE_REPORT: str = os.path.join(_BASE, "reports", "allure-report")
RF_SCRIPTS_DIR: str = os.path.join(_BASE, "tests", "generated")
RF_RESOURCES_DIR: str = os.path.join(_BASE, "tests", "resources")
RF_SCREENSHOTS_DIR: str = os.path.join(_BASE, "reports", "screenshots")
POWERBI_CSV_PATH: str = os.path.join(_BASE, "reports", "powerbi_export.csv")

# ─── Browser ─────────────────────────────────────────────────
BROWSER: str = os.getenv("BROWSER", "Chrome")
SELENIUM_SPEED: str = os.getenv("SELENIUM_SPEED", "0.3s")
SELENIUM_TIMEOUT: str = os.getenv("SELENIUM_TIMEOUT", "30s")
