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


@jira_bp.route("/fetch-ticket-by-key", methods=["POST"])
def fetch_ticket_by_key():
    """Fetch a single Jira ticket by key and auto-generate scenarios.

    Request JSON:
        ticket_key  : str  — e.g. "AS-33" (required)
        jira_url    : str
        username    : str
        api_token   : str
        api_key     : str  — Anthropic key for scenario generation
        app_url     : str  — application URL for test scenarios
    """
    data = request.get_json(force=True, silent=True) or {}

    ticket_key  = data.get("ticket_key", "").strip()
    jira_url    = (data.get("jira_url")    or config.JIRA_BASE_URL).strip()
    username    = (data.get("username")    or config.JIRA_USERNAME).strip()
    api_token   = (data.get("api_token")   or config.JIRA_API_TOKEN).strip()
    api_key     = (data.get("api_key")     or config.ANTHROPIC_API_KEY).strip()
    app_url     = data.get("app_url", "").strip()

    if not ticket_key:
        return jsonify({"success": False, "error": "ticket_key is required (e.g. AS-33)"}), 400

    if not (jira_url and username and api_token):
        return jsonify(
            {"success": False, "error": "Jira credentials required. Fill Jira URL, username, and API token."}
        ), 400

    try:
        from backend.ai_engine import generate_scenarios

        # Step 1: Fetch ticket from Jira
        client = get_jira_client(jira_url, username, api_token)
        ticket = client.get_issue_by_key(ticket_key)

        # Step 2: Build description from ticket details
        desc_parts = []
        desc_parts.append(f"Ticket: {ticket['id']} - {ticket['summary']}")
        if ticket.get("description"):
            desc_parts.append(f"Description: {ticket['description']}")
        if ticket.get("acceptance_criteria"):
            desc_parts.append(f"Acceptance Criteria: {ticket['acceptance_criteria']}")
        full_description = "\n".join(desc_parts)

        # Step 3: Auto-generate scenarios using AI
        scenarios = None
        if api_key:
            try:
                scenarios = generate_scenarios(
                    app_url=app_url,
                    description=full_description,
                    username=data.get("test_username", ""),
                    password=data.get("test_password", ""),
                    api_key=api_key,
                )
            except Exception as ai_err:
                scenarios = None
                ticket["ai_error"] = str(ai_err)

        return jsonify({
            "success": True,
            "ticket": ticket,
            "scenarios": scenarios,
            "description_used": full_description,
        })

    except requests.exceptions.HTTPError as http_err:
        status_code = http_err.response.status_code if http_err.response else 500
        if status_code == 404:
            return jsonify({"success": False, "error": f"Ticket '{ticket_key}' not found in Jira."}), 404
        return jsonify({"success": False, "error": f"Jira error: {http_err}"}), status_code
    except Exception as exc:
        return jsonify({"success": False, "error": str(exc)}), 500


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
