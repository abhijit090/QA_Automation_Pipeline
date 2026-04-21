"""
routes/reports.py
POST /api/generate-report          — build Allure HTML report
GET  /api/report-summary/<run_id>  — pass/fail counts for a run
GET  /api/download-script/<id>     — download generated .robot file
GET  /api/export-powerbi/<run_id>  — download PowerBI CSV
"""

import os

from flask import Blueprint, jsonify, send_file, request

import config
from backend.report_manager import report_manager
from backend.test_runner import test_runner

reports_bp = Blueprint("reports", __name__)


@reports_bp.route("/generate-report", methods=["POST"])
def api_generate_report():
    """Trigger `allure generate` to produce an HTML report."""
    result = report_manager.generate_allure_report()
    status = 200 if result["success"] else 500
    return jsonify(result), status


@reports_bp.route("/report-summary/<run_id>", methods=["GET"])
def api_report_summary(run_id: str):
    """Return pass/fail summary and report availability for *run_id*."""
    summary = report_manager.get_report_summary(run_id)
    return jsonify({"success": True, "summary": summary})


@reports_bp.route("/save-script/<script_id>", methods=["POST"])
def save_script(script_id: str):
    """Persist edited .robot script content sent from the browser editor.

    Request JSON:
        content : str — full .robot file text after user edits
    """
    data    = request.get_json(force=True, silent=True) or {}
    content = data.get("content", "")

    if not content.strip():
        return jsonify({"success": False, "error": "content is empty"}), 400

    filename    = f"test_{script_id}.robot"
    script_path = os.path.join(config.RF_SCRIPTS_DIR, filename)
    os.makedirs(config.RF_SCRIPTS_DIR, exist_ok=True)

    with open(script_path, "w", encoding="utf-8") as fh:
        fh.write(content)

    return jsonify({"success": True, "filename": filename})


@reports_bp.route("/download-script/<script_id>", methods=["GET"])
def download_script(script_id: str):
    """Download a generated .robot file by its ID."""
    filename    = f"test_{script_id}.robot"
    script_path = os.path.join(config.RF_SCRIPTS_DIR, filename)

    if not os.path.isfile(script_path):
        return jsonify({"error": "Script not found"}), 404

    return send_file(
        script_path,
        as_attachment=True,
        download_name=filename,
        mimetype="text/plain",
    )


@reports_bp.route("/export-powerbi/<run_id>", methods=["GET"])
def export_powerbi(run_id: str):
    """Export test results as a CSV file suitable for PowerBI."""
    results = test_runner.get_results(run_id)
    if not results:
        # Try to build results from output.xml if available
        run_dir = os.path.join(config.RF_OUTPUT_DIR, run_id)
        xml_path = os.path.join(run_dir, "output.xml")
        if os.path.isfile(xml_path):
            results = report_manager.get_report_summary(run_id)
            results["tests"] = []
            from xml.etree import ElementTree as ET
            try:
                root = ET.parse(xml_path).getroot()
                for test_el in root.iter("test"):
                    status_el = test_el.find("status")
                    results["tests"].append({
                        "name": test_el.get("name", ""),
                        "status": status_el.get("status", "") if status_el is not None else "",
                        "message": status_el.get("message", "") if status_el is not None else "",
                        "start_time": status_el.get("starttime", "") if status_el is not None else "",
                        "end_time": status_el.get("endtime", "") if status_el is not None else "",
                    })
            except Exception:
                pass
        if not results or not results.get("tests"):
            return jsonify({"error": "Run results not found. Run tests first."}), 404

    csv_path = report_manager.export_powerbi_csv(results)
    return send_file(
        csv_path,
        as_attachment=True,
        download_name=f"qa_results_{run_id[:8]}.csv",
        mimetype="text/csv",
    )


@reports_bp.route("/run-report-files/<run_id>", methods=["GET"])
def run_report_files(run_id: str):
    """Return URLs to the RF HTML report and log for *run_id*."""
    run_dir = os.path.join(config.RF_OUTPUT_DIR, run_id)
    return jsonify(
        {
            "success":   True,
            "report":    f"/run-report/{run_id}/report.html"
                         if os.path.isfile(os.path.join(run_dir, "report.html"))
                         else None,
            "log":       f"/run-report/{run_id}/log.html"
                         if os.path.isfile(os.path.join(run_dir, "log.html"))
                         else None,
            "allure":    "/allure-report/"
                         if os.path.isfile(
                             os.path.join(config.RF_ALLURE_REPORT, "index.html")
                         )
                         else None,
        }
    )


@reports_bp.route("/powerbi-dashboard", methods=["GET"])
def powerbi_dashboard():
    """Generate a beautiful PowerBI-style HTML dashboard from all test runs."""
    from xml.etree import ElementTree as ET
    from datetime import datetime
    from flask import render_template

    output_dir = config.RF_OUTPUT_DIR
    all_runs = []
    all_tests_total = 0
    all_passed_total = 0
    all_failed_total = 0

    # Parse all runs
    if os.path.isdir(output_dir):
        for run_dir_name in sorted(os.listdir(output_dir), reverse=True):
            xml_path = os.path.join(output_dir, run_dir_name, "output.xml")
            if not os.path.isfile(xml_path):
                continue
            try:
                root = ET.parse(xml_path).getroot()
                tests = []
                for t in root.iter("test"):
                    s = t.find("status")
                    status = s.get("status", "") if s is not None else ""
                    msg = s.get("message", "") if s is not None else ""
                    tests.append({"name": t.get("name", ""), "status": status, "message": msg})
                passed = sum(1 for t in tests if t["status"] == "PASS")
                failed = sum(1 for t in tests if t["status"] == "FAIL")
                all_runs.append({
                    "id": run_dir_name[:8],
                    "total": len(tests),
                    "passed": passed,
                    "failed": failed,
                    "tests": tests,
                })
                all_tests_total += len(tests)
                all_passed_total += passed
                all_failed_total += failed
            except Exception:
                continue

    pass_rate = round((all_passed_total / all_tests_total * 100) if all_tests_total > 0 else 0, 1)
    circ = 2 * 3.14159 * 70  # circumference for r=70
    pass_dash = round(circ * pass_rate / 100, 1)
    pass_gap = round(circ - pass_dash, 1)
    fail_pct = 100 - pass_rate
    fail_dash = round(circ * fail_pct / 100, 1)
    fail_gap = round(circ - fail_dash, 1)

    # Bar chart rows (last 8 runs)
    bar_runs = all_runs[:8]
    bar_rows_html = ""
    max_tests = max((r["total"] for r in bar_runs), default=1)
    for r in reversed(bar_runs):
        p_pct = round(r["passed"] / max_tests * 100) if max_tests else 0
        f_pct = round(r["failed"] / max_tests * 100) if max_tests else 0
        bar_rows_html += f'''<div class="bar-row">
          <div class="bar-label">{r["id"]}</div>
          <div class="bar-track">
            <div class="bar-fill mixed-pass" style="width:{p_pct}%">{r["passed"]}</div>
          </div>
          <div class="bar-track" style="max-width:30%">
            <div class="bar-fill mixed-fail" style="width:{f_pct * 3}%">{r["failed"]}</div>
          </div>
          <div class="bar-count">{r["total"]}</div>
        </div>\n'''

    # Test detail rows (latest run)
    test_rows_html = ""
    latest_tests = all_runs[0]["tests"] if all_runs else []
    for i, t in enumerate(latest_tests, 1):
        badge_cls = "pass" if t["status"] == "PASS" else "fail"
        msg = t["message"][:120] if t["message"] else ""
        test_rows_html += f'''<tr>
          <td>{i}</td>
          <td>{t["name"]}</td>
          <td><span class="badge {badge_cls}">{t["status"]}</span></td>
          <td class="msg-cell" title="{msg}">{msg}</td>
        </tr>\n'''

    if not test_rows_html:
        test_rows_html = '<tr><td colspan="4" style="text-align:center;color:#8b949e;padding:20px">No test results available. Run tests first.</td></tr>'

    # Read template and replace placeholders
    template_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "templates", "powerbi_report.html")
    with open(template_path, "r", encoding="utf-8") as f:
        html = f.read()

    html = html.replace("{{generated_at}}", datetime.now().strftime("%B %d, %Y at %I:%M %p"))
    html = html.replace("{{total_runs}}", str(len(all_runs)))
    html = html.replace("{{total_tests}}", str(all_tests_total))
    html = html.replace("{{total_passed}}", str(all_passed_total))
    html = html.replace("{{total_failed}}", str(all_failed_total))
    html = html.replace("{{pass_rate}}", str(pass_rate))
    html = html.replace("{{pass_dash}}", str(pass_dash))
    html = html.replace("{{pass_gap}}", str(pass_gap))
    html = html.replace("{{fail_dash}}", str(fail_dash))
    html = html.replace("{{fail_gap}}", str(fail_gap))
    html = html.replace("{{bar_count}}", str(len(bar_runs)))
    html = html.replace("{{bar_rows}}", bar_rows_html)
    html = html.replace("{{test_rows}}", test_rows_html)

    return html
