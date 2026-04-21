"""
routes/generate.py
POST /api/generate-scenarios  — AI scenario generation
POST /api/generate-script     — Robot Framework script generation
"""

import json
import os
import uuid

from flask import Blueprint, jsonify, request

import config
from backend.ai_engine import generate_robot_script, generate_scenarios

generate_bp = Blueprint("generate", __name__)

# Folder that stores scenario JSON files (one per generation)
_SCENARIOS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tests", "scenarios")


@generate_bp.route("/generate-scenarios", methods=["POST"])
def api_generate_scenarios():
    """Generate positive + negative test scenarios using Claude AI.

    Request JSON:
        app_url     : str  — application under test
        description : str  — test title / scenario description  (required)
        username    : str  — optional login username (used as context)
        password    : str  — optional (not sent to AI, only used as hint flag)
        api_key     : str  — Anthropic API key (overrides .env value)
    """
    data = request.get_json(force=True, silent=True) or {}

    app_url     = data.get("app_url", "").strip()
    description = data.get("description", "").strip()
    username    = data.get("username", "").strip()
    password    = data.get("password", "").strip()
    api_key     = data.get("api_key", "").strip() or config.ANTHROPIC_API_KEY

    if not description:
        return jsonify({"success": False, "error": "description is required"}), 400

    try:
        scenarios = generate_scenarios(app_url, description, username, password, api_key)
        return jsonify({"success": True, "scenarios": scenarios})
    except ValueError as exc:
        return jsonify({"success": False, "error": str(exc)}), 400
    except Exception as exc:
        return jsonify({"success": False, "error": str(exc)}), 500


@generate_bp.route("/generate-script", methods=["POST"])
def api_generate_script():
    """Convert test scenarios into a Robot Framework .robot file.

    Request JSON:
        scenarios   : dict|list — from /generate-scenarios  (required)
        app_url     : str
        username    : str
        password    : str
        suite_name  : str       — optional suite name
        api_key     : str       — optional Anthropic key override
    """
    data = request.get_json(force=True, silent=True) or {}

    scenarios  = data.get("scenarios", [])
    app_url    = data.get("app_url", "").strip()
    username   = data.get("username", "").strip()
    password   = data.get("password", "").strip()
    suite_name = data.get("suite_name", "AI QA Suite").strip()
    api_key    = data.get("api_key", "").strip() or config.ANTHROPIC_API_KEY

    if not scenarios:
        return jsonify({"success": False, "error": "scenarios is required"}), 400

    try:
        script_content = generate_robot_script(
            scenarios, app_url, username, password, suite_name, api_key
        )

        # ── Persist robot script ───────────────────────────────
        script_id = str(uuid.uuid4())[:8]
        filename  = f"test_{script_id}.robot"
        os.makedirs(config.RF_SCRIPTS_DIR, exist_ok=True)
        script_path = os.path.join(config.RF_SCRIPTS_DIR, filename)

        with open(script_path, "w", encoding="utf-8") as fh:
            fh.write(script_content)

        # ── Persist scenarios JSON alongside the script ────────
        os.makedirs(_SCENARIOS_DIR, exist_ok=True)
        scenario_path = os.path.join(_SCENARIOS_DIR, f"scenarios_{script_id}.json")
        with open(scenario_path, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "script_id":  script_id,
                    "app_url":    app_url,
                    "username":   username,
                    "suite_name": suite_name,
                    "scenarios":  scenarios,
                },
                fh,
                indent=2,
            )

        return jsonify(
            {
                "success":       True,
                "script":        script_content,
                "script_id":     script_id,
                "filename":      filename,
                "script_path":   script_path,
                "scenario_file": scenario_path,
            }
        )
    except ValueError as exc:
        return jsonify({"success": False, "error": str(exc)}), 400
    except Exception as exc:
        return jsonify({"success": False, "error": str(exc)}), 500
