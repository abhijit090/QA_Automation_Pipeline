"""
backend/jira_client.py
Jira REST API v2 client.

Capabilities:
  - List Done tickets from the current sprint
  - Create bug tickets for failed tests
  - Connection health-check
"""

import base64
from typing import Dict, List, Optional

import requests

import config


class JiraClient:
    """Thin wrapper around Jira REST API v2."""

    def __init__(
        self,
        base_url: str | None = None,
        username: str | None = None,
        api_token: str | None = None,
    ) -> None:
        self.base_url = (base_url or config.JIRA_BASE_URL).rstrip("/")
        self.username = username or config.JIRA_USERNAME
        self.api_token = api_token or config.JIRA_API_TOKEN

        self._session = requests.Session()
        self._session.headers.update(
            {
                "Content-Type": "application/json",
                "Accept":       "application/json",
            }
        )

        if self.username and self.api_token:
            token = base64.b64encode(
                f"{self.username}:{self.api_token}".encode()
            ).decode()
            self._session.headers["Authorization"] = f"Basic {token}"

    # ── Health ────────────────────────────────────────────────

    def test_connection(self) -> bool:
        """Return True if credentials are valid."""
        try:
            resp = self._session.get(
                f"{self.base_url}/rest/api/2/myself", timeout=8
            )
            return resp.status_code == 200
        except Exception:
            return False

    # ── Read ──────────────────────────────────────────────────

    def get_issue_by_key(self, issue_key: str) -> Dict:
        """Fetch a single Jira issue by its key (e.g. AS-33).

        Uses JIRA_AC_FIELD_MAP from config to find the correct AC custom field
        based on the project key prefix.
        """
        # Determine project key from issue key (e.g. AS-33 -> AS)
        project_prefix = issue_key.split("-")[0] if "-" in issue_key else ""

        # Get the AC custom field for this project
        ac_field = config.JIRA_AC_FIELD_MAP.get(project_prefix, "")
        if not ac_field:
            ac_field = config.JIRA_ACCEPTANCE_CRITERIA_FIELD

        # Build fields list
        fields = "summary,description,status,labels,issuetype,priority,assignee"
        if ac_field:
            fields += f",{ac_field}"

        resp = self._session.get(
            f"{self.base_url}/rest/api/2/issue/{issue_key}",
            params={"fields": fields},
            timeout=15,
        )
        resp.raise_for_status()

        raw = resp.json()
        f = raw.get("fields", {})

        description = f.get("description") or ""
        if isinstance(description, dict):
            description = self._adf_to_text(description)

        # Extract Acceptance Criteria from the mapped custom field
        acceptance_criteria = ""
        if ac_field:
            val = f.get(ac_field)
            if val:
                if isinstance(val, dict):
                    acceptance_criteria = self._adf_to_text(val)
                elif isinstance(val, str):
                    acceptance_criteria = val

        # Fallback: try to extract AC from description text
        if not acceptance_criteria and description:
            import re
            ac_match = re.search(
                r'(?:acceptance criteria|AC|given|scenario)[:\s]*(.*)',
                description,
                re.IGNORECASE | re.DOTALL
            )
            if ac_match:
                acceptance_criteria = ac_match.group(1).strip()[:2000]

        return {
            "id":                  raw.get("key", ""),
            "summary":             f.get("summary", ""),
            "description":         description,
            "acceptance_criteria": acceptance_criteria,
            "status":              (f.get("status") or {}).get("name", ""),
            "labels":              f.get("labels", []),
            "priority":            (f.get("priority") or {}).get("name", "Medium"),
            "type":                (f.get("issuetype") or {}).get("name", ""),
            "assignee":            (f.get("assignee") or {}).get("displayName", "Unassigned"),
        }

    def get_current_sprint_issues(
        self,
        project_key: str | None = None,
        status_filter: str = "Done",
    ) -> List[Dict]:
        """Fetch issues from the open sprint, filtered by *status_filter*.

        Returns a list of simplified issue dicts.
        """
        project = project_key or config.JIRA_PROJECT_KEY
        if not project:
            raise ValueError("project_key is required.")

        jql = (
            f'project = "{project}" '
            f'AND sprint in openSprints() '
            f'AND status = "{status_filter}" '
            f"ORDER BY updated DESC"
        )

        resp = self._session.get(
            f"{self.base_url}/rest/api/2/search",
            params={
                "jql":        jql,
                "fields":     "summary,description,status,labels,issuetype,priority,assignee",
                "maxResults": 100,
            },
            timeout=15,
        )
        resp.raise_for_status()

        issues: List[Dict] = []
        for raw in resp.json().get("issues", []):
            f = raw.get("fields", {})
            description = f.get("description") or ""
            if isinstance(description, dict):
                description = self._adf_to_text(description)

            issues.append(
                {
                    "id":          raw.get("key", ""),
                    "summary":     f.get("summary", ""),
                    "description": description,
                    "status":      (f.get("status") or {}).get("name", ""),
                    "labels":      f.get("labels", []),
                    "priority":    (f.get("priority") or {}).get("name", "Medium"),
                    "type":        (f.get("issuetype") or {}).get("name", ""),
                    "assignee":    (f.get("assignee") or {}).get("displayName", "Unassigned"),
                }
            )
        return issues

    # ── Write ─────────────────────────────────────────────────

    def create_bug(
        self,
        summary: str,
        description: str,
        project_key: str | None = None,
        priority: str = "High",
    ) -> Dict:
        """Create a Bug issue in Jira. Returns {id, url, status}."""
        project = project_key or config.JIRA_PROJECT_KEY
        if not project:
            raise ValueError("project_key is required.")

        resp = self._session.post(
            f"{self.base_url}/rest/api/2/issue",
            json={
                "fields": {
                    "project":     {"key": project},
                    "summary":     summary,
                    "description": description,
                    "issuetype":   {"name": "Bug"},
                    "priority":    {"name": priority},
                }
            },
            timeout=15,
        )
        resp.raise_for_status()
        key = resp.json().get("key", "")
        return {
            "id":     key,
            "url":    f"{self.base_url}/browse/{key}",
            "status": "created",
        }

    # ── Helpers ───────────────────────────────────────────────

    @staticmethod
    def _adf_to_text(node: Dict) -> str:
        """Recursively extract plain text from Atlassian Document Format."""
        parts: List[str] = []

        def _walk(n):
            if isinstance(n, dict):
                if n.get("type") == "text":
                    parts.append(n.get("text", ""))
                for child in n.get("content", []):
                    _walk(child)
            elif isinstance(n, list):
                for item in n:
                    _walk(item)

        _walk(node)
        return " ".join(p for p in parts if p)


# ── Factory ──────────────────────────────────────────────────

def get_jira_client(
    base_url: str | None = None,
    username: str | None = None,
    api_token: str | None = None,
) -> JiraClient:
    return JiraClient(base_url, username, api_token)
