"""
backend/test_runner.py
Robot Framework execution handler.

- Runs robot via subprocess
- Streams every output line to SSEManager
- Parses output.xml to build a structured results dict
- Exposes a singleton `test_runner` used by the routes
"""

import os
import shutil
import subprocess
import threading
from datetime import datetime
from typing import Dict, List, Optional
from xml.etree import ElementTree as ET

import config
from backend.sse_manager import sse_manager


# ─── Level detection ─────────────────────────────────────────

_LEVEL_MAP = {
    "| PASS |": "PASS",
    "| FAIL |": "FAIL",
    "ERROR": "ERROR",
    "WARN":  "WARN",
    "==":    "SEPARATOR",
    "--":    "SEPARATOR",
}


def _detect_level(line: str) -> str:
    line_u = line.upper()
    for token, level in _LEVEL_MAP.items():
        if token in line_u:
            return level
    return "INFO"


# ─── TestRunner ──────────────────────────────────────────────

class TestRunner:
    """Manages Robot Framework subprocess execution."""

    def __init__(self) -> None:
        self.is_running: bool = False
        self._results: Dict[str, Dict] = {}   # run_id → result dict

    # ── Public ────────────────────────────────────────────────

    def run_tests(
        self,
        script_path: str,
        run_id: str,
        variables: Dict[str, str] | None = None,
    ) -> Dict:
        """Start an async Robot Framework execution.

        Logs stream via SSEManager.  Call ``get_results(run_id)`` after the
        SSE stream closes to retrieve the parsed result dict.
        """
        self.is_running = True
        run_output_dir = os.path.join(config.RF_OUTPUT_DIR, run_id)
        os.makedirs(run_output_dir, exist_ok=True)

        # Copy the .robot script into the run folder for traceability
        try:
            shutil.copy2(script_path, os.path.join(run_output_dir, os.path.basename(script_path)))
        except Exception:
            pass

        # Also copy matching scenarios JSON if it exists
        try:
            base_id = os.path.splitext(os.path.basename(script_path))[0].replace("test_", "")
            scenarios_dir = os.path.join(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                "tests", "scenarios",
            )
            scenario_file = os.path.join(scenarios_dir, f"scenarios_{base_id}.json")
            if os.path.isfile(scenario_file):
                shutil.copy2(scenario_file, os.path.join(run_output_dir, "scenarios.json"))
        except Exception:
            pass

        t = threading.Thread(
            target=self._execute,
            args=(script_path, run_id, run_output_dir, variables or {}),
            daemon=True,
        )
        t.start()
        return {"run_id": run_id, "status": "started"}

    def get_results(self, run_id: str) -> Optional[Dict]:
        """Return the result dict for *run_id*, or None if not yet complete."""
        return self._results.get(run_id)

    # ── Private ───────────────────────────────────────────────

    def _execute(
        self,
        script_path: str,
        run_id: str,
        output_dir: str,
        variables: Dict[str, str],
    ) -> None:
        """Run Robot Framework in a subprocess and stream its output."""
        try:
            # ── Wipe previous Allure results so report shows ONLY this run ──
            if os.path.isdir(config.RF_ALLURE_RESULTS):
                shutil.rmtree(config.RF_ALLURE_RESULTS)
            os.makedirs(config.RF_ALLURE_RESULTS, exist_ok=True)

            allure_listener = f"allure_robotframework;{config.RF_ALLURE_RESULTS}"

            cmd: List[str] = [
                "python", "-m", "robot",
                "--outputdir",  output_dir,
                "--output",     "output.xml",
                "--log",        "log.html",
                "--report",     "report.html",
                "--loglevel",   "DEBUG",
                "--listener",   allure_listener,
            ]

            for key, val in variables.items():
                cmd += ["--variable", f"{key}:{val}"]

            cmd.append(script_path)

            sse_manager.push_log(
                f"▶ Starting execution: {os.path.basename(script_path)}", "INFO", run_id
            )
            sse_manager.push_log(f"CMD: {' '.join(cmd)}", "DEBUG", run_id)

            project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1,
                cwd=project_root,
            )

            for raw_line in iter(proc.stdout.readline, ""):
                line = raw_line.rstrip()
                if line:
                    sse_manager.push_log(line, _detect_level(line), run_id)

            proc.wait()
            rc = proc.returncode

            if rc == 0:
                sse_manager.push_log("✅ All tests PASSED.", "PASS", run_id)
            elif rc == 1:
                sse_manager.push_log("❌ Some tests FAILED.", "FAIL", run_id)
            else:
                sse_manager.push_log(f"⚠ Robot exited with code {rc}.", "ERROR", run_id)

            self._results[run_id] = self._parse_output_xml(output_dir, run_id, rc)

        except FileNotFoundError:
            sse_manager.push_log(
                "ERROR: 'python -m robot' not found. Is robotframework installed?",
                "ERROR", run_id,
            )
            self._results[run_id] = {
                "status": "error",
                "error": "Robot Framework not found in PATH",
                "tests": [],
            }
        except Exception as exc:
            sse_manager.push_log(f"FATAL: {exc}", "ERROR", run_id)
            self._results[run_id] = {
                "status": "error",
                "error": str(exc),
                "tests": [],
            }
        finally:
            self.is_running = False
            sse_manager.push_log("Stream closing…", "DONE", run_id)
            sse_manager.end_run(run_id)

    def _parse_output_xml(
        self, output_dir: str, run_id: str, return_code: int
    ) -> Dict:
        """Parse Robot Framework output.xml into a structured dict."""
        result: Dict = {
            "run_id": run_id,
            "status": "pass" if return_code == 0 else "fail",
            "return_code": return_code,
            "output_dir": output_dir,
            "timestamp": datetime.now().isoformat(),
            "total": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "tests": [],
            "report_url": f"/run-report/{run_id}/report.html",
            "log_url":    f"/run-report/{run_id}/log.html",
        }

        xml_path = os.path.join(output_dir, "output.xml")
        if not os.path.exists(xml_path):
            return result

        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()

            for test_el in root.iter("test"):
                status_el = test_el.find("status")
                status = status_el.get("status", "UNKNOWN") if status_el is not None else "UNKNOWN"
                message = status_el.get("message", "") if status_el is not None else ""
                start = status_el.get("starttime", "") if status_el is not None else ""
                end   = status_el.get("endtime",   "") if status_el is not None else ""

                result["tests"].append({
                    "name":       test_el.get("name", ""),
                    "status":     status,
                    "message":    message,
                    "start_time": start,
                    "end_time":   end,
                })

                result["total"] += 1
                if status == "PASS":
                    result["passed"] += 1
                elif status == "FAIL":
                    result["failed"] += 1
                else:
                    result["skipped"] += 1

        except Exception as exc:
            result["parse_error"] = str(exc)

        return result


# ── Singleton ────────────────────────────────────────────────
test_runner = TestRunner()
