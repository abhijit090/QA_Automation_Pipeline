"""
routes/jira.py
POST /api/jira/fetch-tickets   — fetch Done sprint tickets
POST /api/jira/create-bug      — create a bug from a failed test
POST /api/jira/test-connection — verify Jira credentials
"""

from flask import Blueprint, jsonify, request

import config
from backend.ai_engine import enhance_jira_scenario
from backend.jira_client import get_jira_client

jira_bp = Blueprint("jira", __name__)


@jira_bp.route("/fetch-tickets", methods=["POST"])
def fetch_tickets():
    """Fetch Done tickets from the current Jira sprint.

    Request JSON:
        jira_url    : str  — e.g. https://acme.atlassian.net
        username    : str  — Jira account email
        api_token   : str  — Jira API token
        project_key : str  — e.g. "QA"
        api_key     : str  — Anthropic key (to enhance tickets with missing descriptions)
    """
    data = request.get_json(force=True, silent=True) or {}

    jira_url    = (data.get("jira_url")    or config.JIRA_BASE_URL).strip()
    username    = (data.get("username")    or config.JIRA_USERNAME).strip()
    api_token   = (data.get("api_token")   or config.JIRA_API_TOKEN).strip()
    project_key = (data.get("project_key") or config.JIRA_PROJECT_KEY).strip()
    api_key     = (data.get("api_key")     or config.ANTHROPIC_API_KEY).strip()

    if not (jira_url and username and api_token):
        return jsonify(
            {"success": False, "error": "jira_url, username, and api_token are required"}
        ), 400

    try:
        client = get_jira_client(jira_url, username, api_token)

        if not client.test_connection():
            return jsonify(
                {"success": False, "error": "Cannot connect to Jira. Check credentials."}
            ), 401

        issues = client.get_current_sprint_issues(project_key, "Done")

        # Enhance tickets that have no description using Claude
        for issue in issues:
            if not issue.get("description") and api_key:
                try:
                    ai_data = enhance_jira_scenario(issue, api_key)
                    issue["ai_scenarios"] = ai_data
                except Exception:
                    pass  # Enhancement is best-effort

        return jsonify(
            {"success": True, "issues": issues, "count": len(issues)}
        )

    except Exception as exc:
        return jsonify({"success": False, "error": str(exc)}), 500


@jira_bp.route("/create-bug", methods=["POST"])
def create_bug():
    """Create a Bug issue in Jira for a failed test.

    Request JSON:
        jira_url    : str
        username    : str
        api_token   : str
        project_key : str
        summary     : str  — required
        description : str
        priority    : str  — default "High"
    """
    data = request.get_json(force=True, silent=True) or {}

    jira_url    = (data.get("jira_url")    or config.JIRA_BASE_URL).strip()
    username    = (data.get("username")    or config.JIRA_USERNAME).strip()
    api_token   = (data.get("api_token")   or config.JIRA_API_TOKEN).strip()
    project_key = (data.get("project_key") or config.JIRA_PROJECT_KEY).strip()
    summary     = data.get("summary", "").strip()
    description = data.get("description", "").strip()
    priority    = data.get("priority", "High").strip()

    if not summary:
        return jsonify({"success": False, "error": "summary is required"}), 400

    try:
        client = get_jira_client(jira_url, username, api_token)
        issue  = client.create_bug(summary, description, project_key, priority)
        return jsonify({"success": True, "issue": issue})
    except Exception as exc:
        return jsonify({"success": False, "error": str(exc)}), 500


@jira_bp.route("/test-connection", methods=["POST"])
def test_connection():
    """Verify that Jira credentials are valid."""
    data = request.get_json(force=True, silent=True) or {}

    jira_url  = data.get("jira_url",  "").strip()
    username  = data.get("username",  "").strip()
    api_token = data.get("api_token", "").strip()

    try:
        client    = get_jira_client(jira_url, username, api_token)
        connected = client.test_connection()
        return jsonify(
            {
                "success": connected,
                "message": "Connected successfully." if connected else "Connection failed.",
            }
        )
    except Exception as exc:
        return jsonify({"success": False, "error": str(exc)}), 500
