"""
backend/report_manager.py
Manages Allure HTML report generation and PowerBI CSV export.
"""

import csv
import os
import shutil
import subprocess
from datetime import datetime
from typing import Dict, List

import config


class ReportManager:
    """Wraps Allure CLI calls and CSV export logic."""

    # ── Allure ────────────────────────────────────────────────

    def generate_allure_report(self) -> Dict:
        """Run `allure generate` to produce an HTML report from allure-results.

        Returns a dict with keys: success (bool), message (str), report_url (str|None).
        """
        if not os.path.isdir(config.RF_ALLURE_RESULTS) or not os.listdir(config.RF_ALLURE_RESULTS):
            return {
                "success": False,
                "message": "No allure-results found. Run tests first.",
                "report_url": None,
            }

        try:
            # Remove the old HTML report so stale data is never served
            if os.path.isdir(config.RF_ALLURE_REPORT):
                shutil.rmtree(config.RF_ALLURE_REPORT)

            # On Windows, allure is installed as allure.cmd via npm.
            # shell=True is required for Windows to find .cmd files.
            result = subprocess.run(
                [
                    "allure", "generate",
                    config.RF_ALLURE_RESULTS,
                    "--output", config.RF_ALLURE_REPORT,
                    "--clean",
                ],
                capture_output=True,
                text=True,
                timeout=120,
                shell=True,
            )
            if result.returncode == 0:
                return {
                    "success": True,
                    "message": "Allure report generated.",
                    "report_url": "/allure-report/",
                }
            else:
                return {
                    "success": False,
                    "message": f"allure generate failed: {result.stderr.strip()}",
                    "report_url": None,
                }
        except FileNotFoundError:
            return {
                "success": False,
                "message": (
                    "Allure CLI not found. Install it with: "
                    "npm install -g allure-commandline"
                ),
                "report_url": None,
            }
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "message": "allure generate timed out.",
                "report_url": None,
            }

    # ── PowerBI CSV ───────────────────────────────────────────

    def export_powerbi_csv(self, run_results: Dict) -> str:
        """Append run results to the cumulative PowerBI CSV.

        Returns the absolute path to the CSV file.
        """
        os.makedirs(os.path.dirname(config.POWERBI_CSV_PATH), exist_ok=True)

        run_id    = run_results.get("run_id", "unknown")
        timestamp = run_results.get("timestamp", datetime.now().isoformat())
        suite     = run_results.get("suite_name", "")
        env       = run_results.get("environment", "test")

        rows: List[Dict] = []
        for test in run_results.get("tests", []):
            rows.append(
                {
                    "run_id":       run_id,
                    "test_name":    test.get("name", ""),
                    "status":       test.get("status", ""),
                    "start_time":   test.get("start_time", timestamp),
                    "end_time":     test.get("end_time", ""),
                    "message":      test.get("message", ""),
                    "suite":        suite,
                    "environment":  env,
                    "exported_at":  datetime.now().isoformat(),
                }
            )

        if not rows:
            return config.POWERBI_CSV_PATH

        fieldnames = list(rows[0].keys())
        file_exists = os.path.isfile(config.POWERBI_CSV_PATH)

        with open(config.POWERBI_CSV_PATH, "a", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=fieldnames)
            if not file_exists:
                writer.writeheader()
            writer.writerows(rows)

        return config.POWERBI_CSV_PATH

    # ── Summary ───────────────────────────────────────────────

    def get_report_summary(self, run_id: str) -> Dict:
        """Return high-level pass/fail counts for *run_id* using output.xml."""
        from xml.etree import ElementTree as ET

        run_dir = os.path.join(config.RF_OUTPUT_DIR, run_id)
        summary = {
            "run_id":           run_id,
            "total":            0,
            "passed":           0,
            "failed":           0,
            "skipped":          0,
            "report_available": os.path.isfile(os.path.join(run_dir, "report.html")),
            "log_available":    os.path.isfile(os.path.join(run_dir, "log.html")),
        }

        xml_path = os.path.join(run_dir, "output.xml")
        if not os.path.isfile(xml_path):
            return summary

        try:
            root = ET.parse(xml_path).getroot()
            for test_el in root.iter("test"):
                status_el = test_el.find("status")
                status = status_el.get("status", "").upper() if status_el is not None else ""
                summary["total"] += 1
                if status == "PASS":
                    summary["passed"] += 1
                elif status == "FAIL":
                    summary["failed"] += 1
                else:
                    summary["skipped"] += 1
        except Exception:
            pass

        return summary


# ── Singleton ────────────────────────────────────────────────
report_manager = ReportManager()
