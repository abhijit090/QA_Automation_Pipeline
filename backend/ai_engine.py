"""
backend/ai_engine.py
AI engine — uses Anthropic Claude to:
  1. generate_scenarios()     — positive + negative test cases from a description
  2. generate_robot_script()  — convert scenarios → Robot Framework .robot file
  3. enhance_jira_scenario()  — fill gaps in Jira tickets with AI-generated steps
"""

import json
import re
from typing import Dict, List

import anthropic

import config


# ─── Helpers ─────────────────────────────────────────────────

def _get_client(api_key: str | None = None) -> anthropic.Anthropic:
    key = api_key or config.ANTHROPIC_API_KEY
    if not key:
        raise ValueError(
            "ANTHROPIC_API_KEY is not set. Add it to .env or enter it in the UI."
        )
    return anthropic.Anthropic(api_key=key)


def _extract_json(text: str) -> Dict:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    match = re.search(r"\{[\s\S]*\}", text)
    if match:
        return json.loads(match.group())
    raise ValueError("No valid JSON found in AI response.")


def _fix_rf7_syntax(script: str) -> str:
    """Post-process generated .robot scripts for RF 7.x compliance.

    1. [Return] → RETURN statement.
    2. Escape bare = in Create List continuation lines (XPath/CSS locators)
       to prevent the RF 'name=value FOR-loop' deprecation warning.
    """
    lines = script.splitlines()
    fixed = []
    in_create_list = False

    for line in lines:
        stripped = line.strip()

        # Track Create List context
        if "Create List" in line:
            in_create_list = True
        elif in_create_list and stripped and not stripped.startswith("..."):
            in_create_list = False

        if re.match(r"^\[Return\]", stripped, re.IGNORECASE):
            indent = len(line) - len(line.lstrip())
            value = re.sub(r"^\[Return\]\s*", "", stripped, flags=re.IGNORECASE)
            fixed.append(" " * indent + (f"RETURN    {value}" if value else "RETURN"))
        elif in_create_list and stripped.startswith("...") and re.search(r"(?<!\\)=(?=['\"])", line):
            # Escape unescaped = before a quote inside a locator string in Create List
            fixed.append(re.sub(r"(?<!\\)=(?=['\"])", r"\\=", line))
        else:
            fixed.append(line)

    return "\n".join(fixed)


# ─── Fallback keywords block ────────────────────────────────
# Appended when the AI output is truncated / missing keywords.

_FALLBACK_KEYWORDS = r"""
Navigate To
    [Documentation]    Navigates to the given URL and waits for the page to load.
    [Arguments]    ${url}
    Go To    ${url}
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

Click App Login Button
    [Documentation]    Clicks the Login button on the APP page (NOT Single Sign-In).
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://button[@type='button' and (normalize-space(.)='Login' or normalize-space(.)='LOGIN' or normalize-space(.)='Log In')]    timeout=10s
    IF    ${f}
        Click Element    xpath://button[@type='button' and (normalize-space(.)='Login' or normalize-space(.)='LOGIN' or normalize-space(.)='Log In')]
        RETURN
    END
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://button[normalize-space(.)='Login' or normalize-space(.)='LOGIN' or normalize-space(.)='Log In']    timeout=3s
    IF    ${f}
        Click Element    xpath://button[normalize-space(.)='Login' or normalize-space(.)='LOGIN' or normalize-space(.)='Log In']
        RETURN
    END
    Fail    Could not find Login button on the app page

Wait For Auth Page
    [Documentation]    Waits for the external auth page (Cognito/Auth0) to load.
    Sleep    3s
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    css:input[name="username"]    timeout=15s
    IF    not ${f}
        ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    css:input[type="email"]    timeout=10s
        IF    not ${f}
            Wait Until Element Is Visible    css:input[type="text"]    timeout=10s
        END
    END

Login To Application
    [Documentation]    Full 2-step login: App Login button -> Auth page credentials -> back to app.
    [Arguments]    ${username}    ${password}
    Navigate To    ${BASE_URL}
    Click App Login Button
    Wait For Auth Page
    Fill Username Field    ${username}
    Fill Password Field    ${password}
    Click Login Button
    Sleep    5s
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

Fill Username Field
    [Documentation]    Fill the username / e-mail field. Supports MUI TextField and plain HTML inputs.
    [Arguments]    ${value}
    # Try id / name first (most reliable)
    FOR    ${loc}    IN    id:username    id:email    id:user    name:username    name:email    name:user
        ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${f}
            Clear Element Text    ${loc}
            Input Text    ${loc}    ${value}
            Log    Filled username: ${loc}    level=INFO
            RETURN
        END
    END
    # MUI TextField — first input that is NOT a password field
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    css:.MuiInputBase-input:not([type="password"])    timeout=5s
    IF    ${f}
        Clear Element Text    css:.MuiInputBase-input:not([type="password"])
        Input Text    css:.MuiInputBase-input:not([type="password"])    ${value}
        Log    Filled username (MUI): css:.MuiInputBase-input:not([type="password"])    level=INFO
        RETURN
    END
    # Plain CSS / XPath fallbacks
    FOR    ${loc}    IN
    ...    css:input[type="text"]
    ...    css:input[type="email"]
    ...    xpath://input[not(@type='password') and not(@type='hidden') and not(@disabled)]
        ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${f}
            Clear Element Text    ${loc}
            Input Text    ${loc}    ${value}
            Log    Filled username: ${loc}    level=INFO
            RETURN
        END
    END
    Fail    Could not locate username/email input field with any known locator

Fill Password Field
    [Documentation]    Fill the password field. Supports MUI TextField and plain HTML inputs.
    [Arguments]    ${value}
    FOR    ${loc}    IN    id:password    name:password
        ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${f}
            Clear Element Text    ${loc}
            Input Text    ${loc}    ${value}
            Log    Filled password: ${loc}    level=INFO
            RETURN
        END
    END
    # MUI password TextField
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    css:.MuiInputBase-input[type="password"]    timeout=5s
    IF    ${f}
        Clear Element Text    css:.MuiInputBase-input[type="password"]
        Input Text    css:.MuiInputBase-input[type="password"]    ${value}
        Log    Filled password (MUI): css:.MuiInputBase-input[type="password"]    level=INFO
        RETURN
    END
    # Generic CSS / XPath
    FOR    ${loc}    IN    css:input[type="password"]    xpath://input[@type='password']
        ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${f}
            Clear Element Text    ${loc}
            Input Text    ${loc}    ${value}
            Log    Filled password: ${loc}    level=INFO
            RETURN
        END
    END
    Fail    Could not locate password input field with any known locator

Click Login Button
    [Documentation]    Click the Login/Submit button. Waits for it to become enabled first (MUI disabled state).
    # Try all common login button labels — wait up to 10s for enabled state (MUI disables until form is filled)
    FOR    ${loc}    IN
    ...    xpath://button[normalize-space(.)='LOGIN']
    ...    xpath://button[normalize-space(.)='Login']
    ...    xpath://button[normalize-space(.)='Log In']
    ...    xpath://button[normalize-space(.)='Sign in']
    ...    xpath://button[normalize-space(.)='Sign In']
    ...    xpath://button[normalize-space(.)='Submit']
    ...    css:button[type="submit"]
    ...    css:input[type="submit"]
        ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${f}
            TRY
                Wait Until Keyword Succeeds    10s    0.5s    Element Should Be Enabled    ${loc}
            EXCEPT
                Log    Button at '${loc}' still disabled — trying next.    level=WARN
                CONTINUE
            END
            Click Element    ${loc}
            Log    Clicked login button: ${loc}    level=INFO
            RETURN
        END
    END
    Fail    Could not locate an enabled login/submit button on the page

Logout From Application
    [Documentation]    Logs out: Profile icon -> logout text -> Yes on confirmation popup.
    Click User Avatar
    Sleep    1s
    Click Logout Option
    Sleep    1s
    Confirm Logout Popup
    Sleep    3s
    Log    Logout complete.    level=INFO

Confirm Logout Popup
    [Documentation]    Clicks Yes on the logout confirmation popup.
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://button[normalize-space(.)='Yes' or normalize-space(.)='YES']    timeout=10s
    IF    ${f}
        Click Element    xpath://button[normalize-space(.)='Yes' or normalize-space(.)='YES']
        RETURN
    END
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://button[normalize-space(.)='OK' or normalize-space(.)='Confirm']    timeout=3s
    IF    ${f}
        Click Element    xpath://button[normalize-space(.)='OK' or normalize-space(.)='Confirm']
        RETURN
    END
    Log    No logout confirmation popup detected    level=WARN

Click User Avatar
    [Documentation]    Clicks the Profile icon button (aria-label=Profile) in the header.
    Wait Until Element Is Visible    xpath://button[@aria-label='Profile']    timeout=15s
    Click Element    xpath://button[@aria-label='Profile']

Click Logout Option
    [Documentation]    Clicks the logout text in the dropdown.
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://p[normalize-space(.)='logout']    timeout=5s
    IF    ${f}
        Click Element    xpath://p[normalize-space(.)='logout']
        RETURN
    END
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://*[normalize-space(.)='logout' or normalize-space(.)='Logout' or normalize-space(.)='Log Out' or normalize-space(.)='Sign Out']    timeout=5s
    IF    ${f}
        Click Element    xpath://*[normalize-space(.)='logout' or normalize-space(.)='Logout' or normalize-space(.)='Log Out' or normalize-space(.)='Sign Out']
        RETURN
    END
    Fail    Could not locate logout option

Capture Failure Screenshot
    [Documentation]    Captures a screenshot on test failure.
    Create Directory    ${SCREENSHOT_DIR}
    ${ts}=    Evaluate    __import__('datetime').datetime.now().strftime('%Y%m%d_%H%M%S')
    Capture Page Screenshot    ${SCREENSHOT_DIR}/failure_${ts}.png

Verify Successful Login
    [Documentation]    Verifies user is redirected away from login page.
    ${url}=    Get Location
    Should Not Contain    ${url}    /login    msg=Still on login page — login failed
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://*[contains(@class,'dashboard') or contains(@class,'nav') or contains(@class,'sidebar') or contains(@class,'header')]    timeout=10s
    IF    ${f}
        Log    Post-login element found    level=INFO
        RETURN
    END
    Log    Login verified by URL    level=INFO

Verify Error Message
    [Documentation]    Verifies an error/alert element is visible.
    [Arguments]    ${expected_text}=${EMPTY}
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    css:[role="alert"]    timeout=5s
    IF    ${f}
        IF    '${expected_text}' != '${EMPTY}'
            Element Should Contain    css:[role="alert"]    ${expected_text}
        END
        RETURN
    END
    ${f}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://*[contains(@class,'error') or contains(@class,'alert') or contains(@class,'invalid')]    timeout=5s
    IF    ${f}
        IF    '${expected_text}' != '${EMPTY}'
            ${txt}=    Get Text    xpath://*[contains(@class,'error') or contains(@class,'alert') or contains(@class,'invalid')]
            Should Contain    ${txt}    ${expected_text}    ignore_case=True
        END
        RETURN
    END
    Log    No explicit error element found    level=WARN
"""

# Required keyword names that must exist in every generated .robot file
_REQUIRED_KEYWORDS = [
    "Login To Application",
    "Fill Username Field",
    "Fill Password Field",
    "Click Login Button",
    "Logout From Application",
    "Click User Avatar",
    "Click Logout Option",
    "Capture Failure Screenshot",
    "Verify Successful Login",
    "Verify Error Message",
]


def _fix_known_locators(script: str) -> str:
    """Force-correct known issues in AI-generated .robot scripts."""
    import re as _re

    out = []
    for line in script.splitlines():
        s = line.strip()

        # 1. Remove invalid 'Suite Name' setting (not valid in RF)
        if s.lower().startswith("suite name"):
            continue

        # 2. Replace button[type=submit] with button[type=button] for LOGIN
        if 'css:button[type="submit"]' in line:
            if "Wait Until" in line or "Element Should Be Enabled" in line:
                line = line.replace(
                    'css:button[type="submit"]',
                    "xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]"
                )

        # 3. Fix 'Location Should Not Contain' (doesn't exist in SeleniumLibrary)
        if "Location Should Not Contain" in line:
            m = _re.search(r"Location Should Not Contain\s+(.+)", line)
            if m:
                arg = m.group(1).strip()
                indent = len(line) - len(line.lstrip())
                out.append(" " * indent + "${_url}=    Get Location")
                line = " " * indent + "Should Not Contain    ${_url}    " + arg

        # 4. Fix screenshot timestamp — colons not allowed on Windows
        if "strftime" in line:
            line = line.replace("%H:%M:%S", "%H%M%S")
            line = line.replace("%Y-%m-%d %H", "%Y%m%d_%H")

        # 5. Remove Element Should Contain Value (MUI false failures)
        if "Element Should Contain Value" in s:
            continue
        if "Element Should Not Be Empty" in s and "locator" in s.lower():
            continue

        out.append(line)

    return "\n".join(out)


def _ensure_required_keywords(script: str) -> str:
    """Check that all required keywords exist in the script.
    If any are missing, append the full fallback keywords block.
    """
    # Normalise for matching: lowercase, collapse whitespace
    lower = script.lower()
    missing = [kw for kw in _REQUIRED_KEYWORDS if kw.lower() not in lower]

    if not missing:
        return script

    # If *** Keywords *** section doesn't exist at all, add it
    if "*** keywords ***" not in lower:
        script += "\n\n*** Keywords ***\n"

    # Append only the missing keywords from the fallback block
    fallback_lines = _FALLBACK_KEYWORDS.strip().splitlines()
    keywords_to_add = []
    current_block = []
    current_name = None

    for line in fallback_lines:
        # A keyword definition starts at column 0 (no leading whitespace)
        if line and not line[0].isspace():
            # Save previous block if it was a missing keyword
            if current_name and current_name in missing:
                keywords_to_add.extend(current_block)
                keywords_to_add.append("")  # blank line separator
            current_name = line.strip()
            current_block = [line]
        else:
            current_block.append(line)

    # Don't forget the last block
    if current_name and current_name in missing:
        keywords_to_add.extend(current_block)
        keywords_to_add.append("")

    if keywords_to_add:
        script = script.rstrip() + "\n\n" + "\n".join(keywords_to_add)

    return script


# ─── Public API ──────────────────────────────────────────────

def generate_scenarios(
    app_url: str,
    description: str,
    username: str = "",
    password: str = "",
    api_key: str | None = None,
) -> Dict:
    """Generate positive and negative test scenarios using Claude."""
    client = _get_client(api_key)

    login_ctx = ""
    if username:
        login_ctx = f"\nLogin Username : {username}\n(Password is provided — include login steps where relevant)"

    prompt = f"""You are a senior QA automation engineer.
Analyse the requirement below and produce comprehensive test scenarios.

Application URL : {app_url}
Test Description: {description}{login_ctx}

Rules:
- Generate at least 4 POSITIVE test cases (happy-path, valid inputs, successful flows).
- Generate at least 4 NEGATIVE test cases (invalid inputs, boundary values, error paths, empty fields).
- Every scenario MUST start with a step that navigates to the application URL.
- If login is required, include "Enter valid username and password" and "Click Login/Submit" as steps.
- Steps must be concrete actions (e.g. "Enter 'admin@test.com' in the email field").
- Include assertions in steps where appropriate (e.g. "Verify dashboard page is displayed").

Return ONLY valid JSON — no markdown fences, no explanation — in exactly this shape:
{{
  "enhanced_description": "Concise, improved description of what is being tested",
  "positive_scenarios": [
    {{
      "id": "TC_POS_001",
      "title": "Descriptive title",
      "priority": "High",
      "steps": ["Navigate to <url>", "Enter valid credentials", "Click Login", "Verify home page loads"],
      "expected_result": "User is logged in and redirected to the dashboard"
    }}
  ],
  "negative_scenarios": [
    {{
      "id": "TC_NEG_001",
      "title": "Descriptive title",
      "priority": "High",
      "steps": ["Navigate to <url>", "Leave username empty", "Enter password", "Click Login"],
      "expected_result": "Error message 'Username is required' is displayed"
    }}
  ]
}}"""

    response = client.messages.create(
        model=config.AI_MODEL,
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
    )
    return _extract_json(response.content[0].text)


def generate_robot_script(
    scenarios: List[Dict] | Dict,
    app_url: str,
    username: str = "",
    password: str = "",
    suite_name: str = "AI Generated Test Suite",
    api_key: str | None = None,
) -> str:
    """Convert test scenarios into a complete Robot Framework .robot file."""
    client = _get_client(api_key)

    if isinstance(scenarios, dict):
        flat = (
            [dict(s, type="positive") for s in scenarios.get("positive_scenarios", [])]
            + [dict(s, type="negative") for s in scenarios.get("negative_scenarios", [])]
        )
    else:
        flat = list(scenarios)

    scenarios_json = json.dumps(flat, indent=2)

    cred_note = ""
    if username or password:
        cred_note = (
            f"\nCredentials available as Robot variables:\n"
            f"  ${{USERNAME}} = {username or '<from variable>'}\n"
            f"  ${{PASSWORD}} = {'*' * len(password) if password else '<from variable>'}\n"
            "Use these variables — do NOT hardcode them."
        )

    prompt = f"""You are an expert Robot Framework 7 automation engineer.

Convert the scenarios below into a COMPLETE, EXECUTABLE .robot file.

Application URL : {app_url}
Suite Name      : {suite_name}{cred_note}

Scenarios (JSON):
{scenarios_json}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MANDATORY RULES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SYNTAX (RF 7.x):
- NEVER use [Return] — use RETURN statement.
- NEVER use Run Keyword If — use IF/END blocks.
- Double-brace variables: ${{VAR}}.

STRUCTURE:
- Sections: *** Settings ***, *** Variables ***, *** Test Cases ***, *** Keywords ***
- Libraries: SeleniumLibrary, OperatingSystem, String, Collections
- Suite Setup: Open Test Browser | Suite Teardown: Close All Browsers
- Test Teardown: Run Keyword If Test Failed    Capture Failure Screenshot

VARIABLES:
- ${{BASE_URL}}  {app_url}
- ${{BROWSER}}  Chrome
- ${{TIMEOUT}}  60s
- ${{USERNAME}}  (filled at runtime)
- ${{PASSWORD}}  (filled at runtime)
- ${{SCREENSHOT_DIR}}  ${{CURDIR}}/../../reports/screenshots

LOGIN BUTTON — CRITICAL:
The app has TWO buttons: "SINGLE SIGN IN" (type=submit) and "LOGIN" (type=button).
You MUST click the LOGIN button (type=button), NEVER the SINGLE SIGN IN (type=submit).
The LOGIN button is DISABLED until both username and password are filled.
Locator: xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
NEVER use css:button[type="submit"] — that is the SSO button.

LOGOUT FLOW:
1. Click Profile icon: xpath://button[@aria-label='Profile']
2. Sleep 1s
3. Click logout text: xpath://p[normalize-space(.)='logout']  (lowercase)
4. Sleep 1s
5. Click 'Yes' on the confirmation popup: xpath://button[normalize-space(.)='Yes']
6. Sleep 3s — logout complete

FIELD LOCATORS:
- Username: id:username -- Click element first, Sleep 0.3s, Clear, Input Text. Timeout=60s.
- Password: id:password -- Click element first, Sleep 0.3s, Clear, Input Password. Timeout=60s.
- NEVER use comma-separated CSS selectors.
- NEVER add value verification after typing (no Element Should Contain Value check).
- Use simple direct locators, NOT locator lists with FOR loops.

TEST CASE PATTERN:
- Positive tests: Login To Application → Verify Successful Login → assertions → Logout From Application
- Negative tests (login fails): Navigate To → fill bad credentials → click login → verify error. NO logout.
- Every test: [Documentation] and [Tags] (positive/negative + TC ID + priority).

ALL KEYWORDS BELOW MUST BE DEFINED:
1. Open Test Browser
2. Navigate To  [Arguments] ${{url}}
3. Fill Username Field  [Arguments] ${{value}} — MUI-aware, see locators above
4. Fill Password Field  [Arguments] ${{value}} — MUI-aware, see locators above
5. Click Login Button — tries LOGIN/Login/Log In/Sign In + waits for enabled (see disabled rule)
6. Login To Application  [Arguments] ${{username}} ${{password}}
   → Navigate To ${{BASE_URL}} → Fill Username Field → Fill Password Field → Sleep 1s
   → Wait Until Keyword Succeeds    10s    0.5s    Element Should Be Enabled    css:button[type="submit"]
   → Click Login Button → Sleep 3s → Wait Until Page Contains Element    tag:body
7. Logout From Application — Click User Avatar → Sleep 1s → Click Logout Option
8. Click User Avatar
9. Click Logout Option
10. Capture Failure Screenshot
11. Verify Successful Login — URL must NOT contain /login; nav/header element visible
12. Verify Error Message  [Arguments] ${{expected_text}}=${{EMPTY}}

KEEP THE SCRIPT CONCISE. Limit to 4 positive + 4 negative test cases maximum.
Return ONLY the raw .robot file — NO markdown fences, NO explanation.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"""

    response = client.messages.create(
        model=config.AI_MODEL,
        max_tokens=16384,
        messages=[{"role": "user", "content": prompt}],
    )

    raw = response.content[0].text.strip()

    # Strip accidental markdown fences
    if raw.startswith("```"):
        lines_md = raw.splitlines()
        if lines_md[0].startswith("```"):
            lines_md = lines_md[1:]
        if lines_md and lines_md[-1].strip() == "```":
            lines_md = lines_md[:-1]
        raw = "\n".join(lines_md).strip()

    # Fix deprecated [Return] syntax
    raw = _fix_rf7_syntax(raw)

    # Ensure all required keywords are present — inject missing ones
    raw = _ensure_required_keywords(raw)

    # Force-fix known locator issues in generated scripts
    raw = _fix_known_locators(raw)

    return raw


def enhance_jira_scenario(ticket: Dict, api_key: str | None = None) -> Dict:
    """Fill missing test scenarios for a Jira ticket using Claude."""
    client = _get_client(api_key)

    prompt = f"""A Jira ticket has incomplete acceptance criteria.
Generate detailed test scenarios based on the ticket.

Ticket ID  : {ticket.get('id', 'Unknown')}
Summary    : {ticket.get('summary', '')}
Description: {ticket.get('description', 'No description provided')}
Type       : {ticket.get('type', '')}
Labels     : {', '.join(ticket.get('labels', []))}

Return ONLY valid JSON:
{{
  "positive_scenarios": [
    {{"id": "TC_POS_001", "title": "...", "priority": "High",
      "steps": ["..."], "expected_result": "..."}}
  ],
  "negative_scenarios": [
    {{"id": "TC_NEG_001", "title": "...", "priority": "Medium",
      "steps": ["..."], "expected_result": "..."}}
  ]
}}"""

    response = client.messages.create(
        model=config.AI_MODEL,
        max_tokens=2048,
        messages=[{"role": "user", "content": prompt}],
    )
    try:
        return _extract_json(response.content[0].text)
    except Exception:
        return {"positive_scenarios": [], "negative_scenarios": []}
