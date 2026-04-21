"""
routes/run_tests.py
POST /api/run-execution    — kick off Robot Framework execution
GET  /api/run-status/<id>  — poll execution status / results
"""

import os
import uuid

from flask import Blueprint, jsonify, request

import config
from backend.sse_manager import sse_manager
from backend.test_runner import test_runner

run_tests_bp = Blueprint("run_tests", __name__)


@run_tests_bp.route("/run-execution", methods=["POST"])
def api_run_execution():
    """Start a Robot Framework test run asynchronously.

    Request JSON (provide *one* of script_id or script_content):
        script_id      : str — ID returned by /generate-script
        script_content : str — raw .robot file content to save + run
        app_url        : str — forwarded to RF as ${BASE_URL}
        username       : str — forwarded as ${USERNAME}
        password       : str — forwarded as ${PASSWORD}

    Response JSON:
        run_id : str  — use with /api/stream/<run_id> for SSE log feed
        status : str  — always "started" on success
    """
    if test_runner.is_running:
        return jsonify({"success": False, "error": "A test run is already in progress."}), 409

    data = request.get_json(force=True, silent=True) or {}

    script_id      = data.get("script_id", "").strip()
    script_content = data.get("script_content", "").strip()
    app_url        = data.get("app_url", "").strip()
    username       = data.get("username", "").strip()
    password       = data.get("password", "").strip()

    # Resolve script path
    if script_id:
        script_path = os.path.join(config.RF_SCRIPTS_DIR, f"test_{script_id}.robot")
    elif script_content:
        new_id      = str(uuid.uuid4())[:8]
        script_id   = new_id
        script_path = os.path.join(config.RF_SCRIPTS_DIR, f"test_{new_id}.robot")
        os.makedirs(config.RF_SCRIPTS_DIR, exist_ok=True)
        with open(script_path, "w", encoding="utf-8") as fh:
            fh.write(script_content)
    else:
        return jsonify({"success": False, "error": "script_id or script_content is required"}), 400

    if not os.path.isfile(script_path):
        return jsonify({"success": False, "error": f"Script not found: {script_path}"}), 404

    # Build RF variables
    variables: dict = {}
    if app_url:
        variables["BASE_URL"] = app_url
    if username:
        variables["USERNAME"] = username
    if password:
        variables["PASSWORD"] = password

    # Create SSE queue and start run
    run_id = str(uuid.uuid4())
    sse_manager.create_run(run_id)
    test_runner.run_tests(script_path, run_id, variables)

    return jsonify({"success": True, "run_id": run_id, "status": "started"})


@run_tests_bp.route("/run-status/<run_id>", methods=["GET"])
def api_run_status(run_id: str):
    """Poll results for *run_id*.  Returns null results while still running."""
    results = test_runner.get_results(run_id)
    return jsonify(
        {
            "success":    True,
            "is_running": test_runner.is_running,
            "results":    results,
        }
    )
