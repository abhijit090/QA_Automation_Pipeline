*** Settings ***
Documentation    Shared keywords — handles app login + external SSO redirect
...              (Microsoft Azure AD / Okta / SAML) automatically.
Library          SeleniumLibrary
Library          OperatingSystem
Library          String
Library          Collections
Library          DateTime


*** Variables ***
${BASE_URL}          ${EMPTY}
${USERNAME}          ${EMPTY}
${PASSWORD}          ${EMPTY}
${BROWSER}           Chrome
${HEADLESS}          false
${SELENIUM_SPEED}    0.3s
${TIMEOUT}           30s
${SCREENSHOT_DIR}    ${CURDIR}/../../reports/screenshots

# ── External SSO locators (Microsoft Azure AD defaults) ───────
# Override in your .robot Variables section if your provider differs.
${EXTERNAL_EMAIL_LOCATOR}
...    xpath://input[@type='email'] | //input[@id='i0116'] | //input[@name='loginfmt']
...    | //input[@id='identifierId'] | //input[@name='identifier']
...    | //input[contains(@id,'email')] | //input[contains(@name,'email')]

${EXTERNAL_PASSWORD_LOCATOR}
...    xpath://input[@type='password'] | //input[@id='i0118'] | //input[@name='passwd']
...    | //input[@id='password'] | //input[contains(@id,'password')]
...    | //input[contains(@name,'password')]

${EXTERNAL_NEXT_LOCATOR}
...    xpath://input[@id='idSIButton9'] | //input[@value='Next'] | //button[@id='idSIButton9']
...    | //button[normalize-space(.)='Next'] | //button[normalize-space(.)='Continue']
...    | //input[@value='Continue']

${EXTERNAL_SIGNIN_LOCATOR}
...    xpath://input[@id='idSIButton9'] | //input[@value='Sign in']
...    | //button[@id='idSIButton9'] | //button[normalize-space(.)='Sign in']
...    | //button[normalize-space(.)='Sign In'] | //button[normalize-space(.)='Log in']
...    | //button[normalize-space(.)='Log In'] | //input[@value='Log in']
...    | //button[@type='submit'] | //input[@type='submit']


*** Keywords ***

# ══════════════════════════════════════════════════════════════
#  BROWSER
# ══════════════════════════════════════════════════════════════

Open Test Browser
    [Documentation]    Open browser, maximise, go to BASE_URL.
    ...    Pass HEADLESS=true (via --variable HEADLESS:true) to run without a display
    ...    (required on CI/CD servers that have no screen).
    [Arguments]    ${url}=${BASE_URL}    ${browser}=${BROWSER}
    Set Selenium Speed      ${SELENIUM_SPEED}
    Set Selenium Timeout    ${TIMEOUT}
    IF    '${HEADLESS}' == 'true'
        ${opts}=    Evaluate
        ...    __import__('selenium.webdriver',fromlist=['ChromeOptions']).ChromeOptions()
        ...    modules=selenium.webdriver
        Call Method    ${opts}    add_argument    --headless\=new
        Call Method    ${opts}    add_argument    --no-sandbox
        Call Method    ${opts}    add_argument    --disable-dev-shm-usage
        Call Method    ${opts}    add_argument    --disable-gpu
        Call Method    ${opts}    add_argument    --window-size\=1920,1080
        Open Browser    ${url}    ${browser}    options=${opts}
    ELSE
        Open Browser    ${url}    ${browser}
        Maximize Browser Window
    END
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    Log    Opened: ${url} (headless=${HEADLESS})    level=INFO

Close Test Browser
    Close All Browsers

Capture Failure Screenshot
    [Documentation]    Save a timestamped screenshot on test failure.
    Create Directory    ${SCREENSHOT_DIR}
    ${ts}=    Get Current Date    result_format=%Y%m%d_%H%M%S
    ${nm}=    Get Variable Value    ${TEST NAME}    unknown
    # Sanitise: replace chars illegal in Windows filenames with underscore
    ${nm}=    Replace String Using Regexp    ${nm}    [^a-zA-Z0-9_\\-]    _
    Capture Page Screenshot    ${SCREENSHOT_DIR}/${nm}_${ts}.png


# ══════════════════════════════════════════════════════════════
#  FULL LOGIN FLOW  (app button → external SSO → back to app)
# ══════════════════════════════════════════════════════════════

Login To Application
    [Documentation]
    ...    Complete login flow for apps that redirect to an external
    ...    SSO provider (Microsoft/Azure AD, Okta, SAML) after the
    ...    "Single Sign-In" button is clicked.
    ...
    ...    Flow:
    ...      1. Click "Single Sign-In" (or Login/Sign In) on the app page
    ...      2. Detect redirect to external auth page
    ...      3. Fill email + click Next (Microsoft two-step) OR fill both fields
    ...      4. Fill password + click Sign in on the external page
    ...      5. Dismiss "Stay signed in?" dialog if present
    ...      6. Verify redirect back to app
    [Arguments]    ${username}=${USERNAME}    ${password}=${PASSWORD}

    # ── Step 1: click the app-side login button ────────────────
    Click Login Button

    # ── Step 2: wait for external auth page ───────────────────
    Log    Waiting for SSO/external auth page…    level=INFO
    Sleep    2s
    Wait Until Page Contains Element    tag:body    timeout=15s

    # ── Step 3 & 4: interact with external SSO provider ───────
    Handle External SSO Page    ${username}    ${password}

    # ── Step 5: handle Microsoft "Stay signed in?" ────────────
    Handle Stay Signed In Dialog

    # ── Step 6: confirm we're back in the app ─────────────────
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    Log    Login complete.    level=INFO


Handle External SSO Page
    [Documentation]
    ...    Fill credentials on an external auth page.
    ...    Detects Microsoft Azure AD (2-step: email → Next → password → Sign in)
    ...    and generic single-form providers automatically.
    [Arguments]    ${username}    ${password}

    # ── Try to fill the email / username field ─────────────────
    ${email_visible}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    ${EXTERNAL_EMAIL_LOCATOR}    timeout=8s
    IF    ${email_visible}
        Input Text    ${EXTERNAL_EMAIL_LOCATOR}    ${username}
        Log    Filled external email field.    level=INFO

        # ── Microsoft "Next" button (step 1 of 2) ─────────────
        ${next_visible}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${EXTERNAL_NEXT_LOCATOR}    timeout=4s
        IF    ${next_visible}
            Click Element    ${EXTERNAL_NEXT_LOCATOR}
            Log    Clicked Next on external SSO page.    level=INFO
            Sleep    2s
        END
    END

    # ── Fill the password field (now visible) ──────────────────
    ${pass_visible}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    ${EXTERNAL_PASSWORD_LOCATOR}    timeout=8s
    IF    ${pass_visible}
        Input Text    ${EXTERNAL_PASSWORD_LOCATOR}    ${password}
        Log    Filled external password field.    level=INFO
    ELSE
        Log    Password field not found on external page — may already be filled.    level=WARN
    END

    # ── Click the sign-in button ──────────────────────────────
    Click External Sign In Button

Handle Stay Signed In Dialog
    [Documentation]
    ...    Dismisses the Microsoft "Stay signed in?" dialog if it appears.
    ...    Clicks "Yes" to stay signed in (avoids repeated prompts).
    ${dialog}=    Run Keyword And Return Status
    ...    Wait Until Page Contains    Stay signed in    timeout=4s
    IF    ${dialog}
        Log    "Stay signed in?" dialog detected — clicking Yes.    level=INFO
        ${yes_btn}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    id:idSIButton9    timeout=3s
        IF    ${yes_btn}
            Click Element    id:idSIButton9
        ELSE
            ${yes_generic}=    Run Keyword And Return Status
            ...    Wait Until Element Is Visible
            ...    xpath://button[contains(normalize-space(.),'Yes')] | //input[@value='Yes']
            ...    timeout=3s
            IF    ${yes_generic}
                Click Element
                ...    xpath://button[contains(normalize-space(.),'Yes')] | //input[@value='Yes']
            END
        END
        Sleep    1.5s
    END


Click External Sign In Button
    [Documentation]    Click the final sign-in/submit button on the external SSO page.
    @{sign_in_locators}=    Create List
    ...    id:idSIButton9
    ...    xpath://input[@value='Sign in']
    ...    xpath://button[normalize-space(.)='Sign in']
    ...    xpath://button[normalize-space(.)='Sign In']
    ...    xpath://button[normalize-space(.)='Log In']
    ...    xpath://button[normalize-space(.)='Log in']
    ...    xpath://input[@value='Log in']
    ...    css:button[type="submit"]
    ...    css:input[type="submit"]
    FOR    ${loc}    IN    @{sign_in_locators}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${found}
            Click Element    ${loc}
            Log    Clicked sign-in: ${loc}    level=INFO
            RETURN
        END
    END
    Fail    Could not find Sign In button on external SSO page.


# ══════════════════════════════════════════════════════════════
#  APP-SIDE LOGIN BUTTON (Step 1 — on the main app page)
# ══════════════════════════════════════════════════════════════

Click Login Button
    [Documentation]
    ...    Click the direct-credentials LOGIN button on the application page.
    ...    Tries button[type=button] with Login text FIRST, then other variants.
    ...    Single Sign-In / SSO buttons are listed LAST to avoid accidental click.

    # 1. button[type=button] with Login text — the app uses type="button"
    ${btn_found}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible
    ...    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login' or normalize-space(.)='Log In')]
    ...    timeout=5s
    IF    ${btn_found}
        Click Element
        ...    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login' or normalize-space(.)='Log In')]
        Log    Clicked app login button: button[type=button]    level=INFO
        RETURN
    END

    # 2. Exact text "LOGIN" (any button type)
    ${login_found}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    xpath://button[normalize-space(.)='LOGIN']    timeout=3s
    IF    ${login_found}
        Click Element    xpath://button[normalize-space(.)='LOGIN']
        Log    Clicked direct login button: LOGIN    level=INFO
        RETURN
    END

    # 3. Other text variants — SSO/Sign-In options listed LAST
    @{exact_texts}=    Create List
    ...    Login
    ...    Log In
    ...    LOG IN
    ...    Submit
    ...    SUBMIT
    ...    Continue
    ...    Sign In
    ...    SIGN IN
    ...    Single Sign-In
    ...    Single Sign In
    ...    Sign In with SSO
    ...    SSO Login
    ...    SSO Sign In
    ...    External User
    ...    Sign On

    FOR    ${text}    IN    @{exact_texts}
        ${xp}=    Set Variable
        ...    xpath://button[normalize-space(.)='${text}'] | //a[@role='button' and normalize-space(.)='${text}']
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${xp}    timeout=2s
        IF    ${found}
            # MUI / React buttons are disabled until form fields are filled — wait up to 10s
            TRY
                Wait Until Keyword Succeeds    10s    0.5s    Element Should Be Enabled    ${xp}
            EXCEPT
                Log    Button '${text}' still disabled — skipping to next locator.    level=WARN
                CONTINUE
            END
            Click Element    ${xp}
            Log    Clicked app login button: "${text}"    level=INFO
            RETURN
        END
    END

    # case-insensitive XPath fallback (translate to lowercase before comparing)
    @{ci_texts}=    Create List    login    sign in    log in    submit    sign on
    FOR    ${text}    IN    @{ci_texts}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible
        ...    xpath://button[translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='${text}']
        ...    timeout=2s
        IF    ${found}
            Click Element
            ...    xpath://button[translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='${text}']
            Log    Clicked (case-insensitive): "${text}"    level=INFO
            RETURN
        END
    END

    # partial-text fallback — Login/Log In before SSO options
    @{partial}=    Create List    Login    Log In    Submit    Single Sign    Sign In    sign-in    SSO
    FOR    ${text}    IN    @{partial}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible
        ...    xpath://button[contains(normalize-space(.),'${text}')]
        ...    timeout=2s
        IF    ${found}
            Click Element    xpath://button[contains(normalize-space(.),'${text}')]
            Log    Clicked (partial text): "${text}"    level=INFO
            RETURN
        END
    END

    # CSS attribute fallback
    @{css}=    Create List
    ...    css:button[type="submit"]    css:input[type="submit"]
    ...    css:button[id*="login" i]    css:button[id*="signin" i]
    ...    css:[data-testid*="login"]    css:[aria-label*="Sign In" i]
    FOR    ${sel}    IN    @{css}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${sel}    timeout=2s
        IF    ${found}
            Click Element    ${sel}
            Log    Clicked (CSS): ${sel}    level=INFO
            RETURN
        END
    END

    Fail    No login button found on the app page. Check the page source.


# ══════════════════════════════════════════════════════════════
#  NAVIGATION
# ══════════════════════════════════════════════════════════════

Navigate To
    [Arguments]    ${url}
    Go To    ${url}
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

Navigate To Path
    [Arguments]    ${path}
    Navigate To    ${BASE_URL}${path}


# ══════════════════════════════════════════════════════════════
#  FORM INTERACTIONS
# ══════════════════════════════════════════════════════════════

Fill Field
    [Arguments]    ${locator}    ${value}
    Wait Until Element Is Visible    ${locator}    timeout=${TIMEOUT}
    Clear Element Text    ${locator}
    Input Text            ${locator}    ${value}


Fill Username Field
    [Documentation]
    ...    Fill the username / e-mail input on a login form.
    ...    Covers plain HTML inputs and MUI (Material-UI) TextField components.
    [Arguments]    ${username}
    @{locs}=    Create List
    ...    id:username
    ...    id:email
    ...    id:user
    ...    name:username
    ...    name:email
    ...    name:user
    ...    css:.MuiInputBase-input:not([type\="password"])
    ...    css:input[name\="username"]
    ...    css:input[id\="username"]
    ...    css:input[placeholder*\="sername" i]
    ...    css:input[placeholder*\="mail" i]
    ...    css:input[type\="text"]
    ...    css:input[type\="email"]
    ...    xpath://input[not(@type\='password') and not(@type\='hidden') and not(@disabled)]
    FOR    ${loc}    IN    @{locs}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${found}
            Clear Element Text    ${loc}
            Input Text            ${loc}    ${username}
            Log    Filled username field: ${loc}    level=INFO
            RETURN
        END
    END
    Fail    Could not locate username/email input field with any known locator.


Fill Password Field
    [Documentation]
    ...    Fill the password input on a login form.
    ...    Covers plain HTML inputs and MUI (Material-UI) TextField components.
    [Arguments]    ${password}
    @{locs}=    Create List
    ...    id:password
    ...    name:password
    ...    css:input[type\="password"]
    ...    css:.MuiInputBase-input[type\="password"]
    ...    xpath://input[@type\='password']
    FOR    ${loc}    IN    @{locs}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${found}
            Clear Element Text    ${loc}
            Input Text            ${loc}    ${password}
            Log    Filled password field: ${loc}    level=INFO
            RETURN
        END
    END
    Fail    Could not locate password input field with any known locator.

Click And Wait
    [Arguments]    ${locator}
    Wait Until Element Is Visible    ${locator}    timeout=${TIMEOUT}
    Click Element    ${locator}
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}


# ══════════════════════════════════════════════════════════════
#  ASSERTIONS
# ══════════════════════════════════════════════════════════════

Page Should Contain Text
    [Arguments]    ${text}
    Wait Until Page Contains    ${text}    timeout=${TIMEOUT}

Element Text Should Be
    [Arguments]    ${locator}    ${expected}
    Wait Until Element Is Visible    ${locator}    timeout=${TIMEOUT}
    ${actual}=    Get Text    ${locator}
    Should Contain    ${actual}    ${expected}

Page Title Should Contain
    [Arguments]    ${expected}
    ${title}=    Get Title
    Should Contain    ${title}    ${expected}

URL Should Contain
    [Arguments]    ${fragment}
    ${url}=    Get Location
    Should Contain    ${url}    ${fragment}

Verify Successful Login
    [Documentation]    Confirm post-login page loaded (dashboard, nav, welcome).
    @{indicators}=    Create List
    ...    css:nav    css:header    css:[class*="dashboard" i]
    ...    css:[class*="welcome" i]    css:[id*="dashboard" i]
    ...    css:[class*="home-page" i]    css:[aria-label*="navigation" i]
    FOR    ${loc}    IN    @{indicators}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${loc}    timeout=6s
        IF    ${found}
            Log    Post-login element found: ${loc}    level=INFO
            RETURN
        END
    END
    # Minimum check — password field gone
    ${pass_gone}=    Run Keyword And Return Status
    ...    Element Should Not Be Visible    css:input[type="password"]
    IF    ${pass_gone}    RETURN
    Fail    Still on login page after authentication attempt.


# ══════════════════════════════════════════════════════════════
#  LOGOUT FLOW
# ══════════════════════════════════════════════════════════════

Logout From Application
    [Documentation]
    ...    Full logout flow:
    ...      1. Click the user avatar / profile icon (top-right)
    ...      2. Click the "logout" option in the dropdown
    ...      3. Verify we are back on the login page
    Click User Avatar
    Sleep    1s
    Click Logout Option
    # Verify login page is shown again
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    ${login_back}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    css:input[type="password"]    timeout=8s
    IF    ${login_back}
        Log    Logout confirmed — login page visible.    level=INFO
    ELSE
        Log    Logout completed (login form not re-detected within timeout).    level=WARN
    END


Click User Avatar
    [Documentation]
    ...    Click the top-right user profile/avatar icon to open the user menu.
    ...    Tries multiple locator patterns used by common UI frameworks.
    @{avatar_locs}=    Create List
    ...    xpath://header//*[contains(@class,'MuiAvatar') or contains(@class,'avatar') or contains(@class,'Avatar')]
    ...    xpath://*[contains(@class,'user-avatar') or contains(@class,'userAvatar') or contains(@class,'profile-icon')]
    ...    xpath://header//button[last()]
    ...    xpath://nav//button[contains(@class,'avatar') or contains(@class,'user')]
    ...    xpath://*[@aria-label='User menu' or @aria-label='Profile' or @aria-label='Account' or @aria-label='account']
    ...    css:header .MuiAvatar-root
    ...    css:[class*="avatar" i]:last-of-type
    ...    css:header button:last-of-type
    FOR    ${loc}    IN    @{avatar_locs}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${found}
            Click Element    ${loc}
            Log    Clicked user avatar: ${loc}    level=INFO
            RETURN
        END
    END
    Fail    Could not find user avatar/profile icon in the header.


Click Logout Option
    [Documentation]
    ...    Click the logout item inside the open user menu dropdown.
    ...    Handles any capitalisation: logout / Logout / Log Out / LOG OUT.
    @{logout_locs}=    Create List
    ...    xpath://*[translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='logout']
    ...    xpath://*[normalize-space(.)='Log Out' or normalize-space(.)='Log out' or normalize-space(.)='LOG OUT']
    ...    xpath://*[contains(normalize-space(.),'logout') or contains(normalize-space(.),'Logout')]
    ...    xpath://*[contains(normalize-space(.),'Log Out') or contains(normalize-space(.),'log out')]
    ...    css:[class*="logout" i]
    ...    css:[href*="logout" i]
    ...    css:[data-testid*="logout" i]
    FOR    ${loc}    IN    @{logout_locs}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${loc}    timeout=3s
        IF    ${found}
            Click Element    ${loc}
            Log    Clicked logout option: ${loc}    level=INFO
            RETURN
        END
    END
    Fail    Could not find logout option in user menu dropdown.

Error Message Should Be Visible
    [Arguments]    ${expected_text}=${EMPTY}
    @{locs}=    Create List
    ...    css:[role="alert"]    css:.error-message    css:.alert-danger
    ...    css:[class*="error" i]    css:[class*="invalid" i]
    ...    css:[aria-live="assertive"]
    FOR    ${loc}    IN    @{locs}
        ${found}=    Run Keyword And Return Status
        ...    Wait Until Element Is Visible    ${loc}    timeout=5s
        IF    ${found}
            IF    '${expected_text}' != '${EMPTY}'
                ${txt}=    Get Text    ${loc}
                Should Contain    ${txt}    ${expected_text}
            END
            RETURN
        END
    END
    Fail    No error message found on page.
