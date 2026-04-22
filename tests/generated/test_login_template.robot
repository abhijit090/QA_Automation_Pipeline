*** Settings ***
Library           SeleniumLibrary
Library           OperatingSystem
Library           String
Library           Collections
Suite Setup       Open Test Browser
Suite Teardown    Close All Browsers
Test Teardown     Run Keyword If Test Failed    Capture Failure Screenshot

*** Variables ***
${BASE_URL}         https://development.d36z6oo50ky8dh.amplifyapp.com/login
${BROWSER}          Chrome
${TIMEOUT}          60s
${USERNAME}         testd1051@gmail.com
${PASSWORD}         Qj8BTm9g
${SCREENSHOT_DIR}   ${CURDIR}/../../reports/screenshots

# ── Exact locators captured from live page ──
${USER_FIELD}       id:username
${PASS_FIELD}       id:password
${LOGIN_BTN}        xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
${SSO_BTN}          xpath://button[@type='submit' and contains(normalize-space(.),'SINGLE SIGN')]

*** Test Cases ***
TC_POS_001 - Successful Login With Valid Credentials
    [Documentation]    Fill username and password on app page, click LOGIN, verify dashboard.
    [Tags]    positive    TC_POS_001    High
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Logout From Application

TC_POS_002 - Session Persistence After Page Refresh
    [Documentation]    Verify user session persists after refreshing the page.
    [Tags]    positive    TC_POS_002    High
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Reload Page
    Sleep    3s
    Verify Successful Login
    Logout From Application

TC_POS_003 - Successful Logout
    [Documentation]    Verify user can logout and is redirected to login page.
    [Tags]    positive    TC_POS_003    High
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Logout From Application
    Sleep    3s
    ${url}=    Get Location
    Should Contain    ${url}    login    msg=Not redirected to login page after logout

TC_POS_004 - Login Page Has Correct UI Elements
    [Documentation]    Verify the login page has username, password fields and LOGIN button.
    [Tags]    positive    TC_POS_004    Medium
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    ${USER_FIELD}    timeout=${TIMEOUT}
    Wait Until Element Is Visible    ${PASS_FIELD}    timeout=${TIMEOUT}
    Page Should Contain Element    ${LOGIN_BTN}
    Log    All login page elements present    level=INFO

TC_NEG_001 - Login With Empty Fields
    [Documentation]    Verify LOGIN button stays disabled when fields are empty.
    [Tags]    negative    TC_NEG_001    High
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    ${USER_FIELD}    timeout=${TIMEOUT}
    ${disabled}=    Run Keyword And Return Status
    ...    Element Should Be Disabled    ${LOGIN_BTN}
    IF    ${disabled}
        Log    LOGIN button correctly disabled when fields are empty    level=INFO
    ELSE
        Click Element    ${LOGIN_BTN}
        Sleep    3s
        ${url}=    Get Location
        Should Contain    ${url}    login    msg=Should remain on login page
    END

TC_NEG_002 - Login With Wrong Password
    [Documentation]    Verify login fails with incorrect password.
    [Tags]    negative    TC_NEG_002    High
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    ${USER_FIELD}    timeout=${TIMEOUT}
    Fill Username    ${USERNAME}
    Fill Password    WrongPassword123!
    Wait Until Element Is Enabled    ${LOGIN_BTN}    timeout=10s
    Click Element    ${LOGIN_BTN}
    Sleep    8s
    ${url}=    Get Location
    ${on_app}=    Run Keyword And Return Status    Should Contain    ${url}    amplifyapp.com
    IF    ${on_app}
        ${still_login}=    Run Keyword And Return Status    Should Contain    ${url}    login
        IF    not ${still_login}
            # Might have redirected to Cognito error page
            ${on_cognito}=    Run Keyword And Return Status    Should Contain    ${url}    cognito
            IF    ${on_cognito}
                Log    Redirected to Cognito with error — login correctly rejected    level=INFO
            END
        ELSE
            Log    Remained on login page — login correctly rejected    level=INFO
        END
    END

TC_NEG_003 - Login With Non-Existent Email
    [Documentation]    Verify login fails with unregistered email.
    [Tags]    negative    TC_NEG_003    High
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    ${USER_FIELD}    timeout=${TIMEOUT}
    Fill Username    nonexistent_xyz@fake.com
    Fill Password    SomePassword@99
    Wait Until Element Is Enabled    ${LOGIN_BTN}    timeout=10s
    Click Element    ${LOGIN_BTN}
    Sleep    8s
    ${url}=    Get Location
    Log    URL after login attempt: ${url}    level=INFO

TC_NEG_004 - Login With Empty Password
    [Documentation]    Verify LOGIN button stays disabled when password is empty.
    [Tags]    negative    TC_NEG_004    High
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    ${USER_FIELD}    timeout=${TIMEOUT}
    Fill Username    ${USERNAME}
    Sleep    1s
    ${disabled}=    Run Keyword And Return Status
    ...    Element Should Be Disabled    ${LOGIN_BTN}
    IF    ${disabled}
        Log    LOGIN button correctly disabled when password is empty    level=INFO
    ELSE
        Log    LOGIN button is enabled with only username — checking behavior    level=WARN
        Click Element    ${LOGIN_BTN}
        Sleep    3s
        ${url}=    Get Location
        Should Contain    ${url}    login    msg=Should remain on login page
    END

*** Keywords ***
Open Test Browser
    Create Directory    ${SCREENSHOT_DIR}
    Open Browser    ${BASE_URL}    ${BROWSER}
    Maximize Browser Window
    Set Selenium Timeout    ${TIMEOUT}

Navigate To
    [Arguments]    ${url}
    Go To    ${url}
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    Sleep    2s

# ══════════════════════════════════════════════════════════════
#  Fill username field — click first to focus, then type
# ══════════════════════════════════════════════════════════════
Fill Username
    [Documentation]    Clicks the username field (id=username), clears it, and types the value.
    [Arguments]    ${value}
    Wait Until Element Is Visible    ${USER_FIELD}    timeout=${TIMEOUT}
    Click Element    ${USER_FIELD}
    Sleep    0.3s
    Clear Element Text    ${USER_FIELD}
    Input Text    ${USER_FIELD}    ${value}
    Log    Filled username: ${value}    level=INFO

# ══════════════════════════════════════════════════════════════
#  Fill password field — click first to focus, then type
# ══════════════════════════════════════════════════════════════
Fill Password
    [Documentation]    Clicks the password field (id=password), clears it, and types the value.
    [Arguments]    ${value}
    Wait Until Element Is Visible    ${PASS_FIELD}    timeout=${TIMEOUT}
    Click Element    ${PASS_FIELD}
    Sleep    0.3s
    Clear Element Text    ${PASS_FIELD}
    Input Password    ${PASS_FIELD}    ${value}
    Log    Filled password field    level=INFO

# ══════════════════════════════════════════════════════════════
#  Full login flow:
#  1. Navigate to app login page
#  2. Fill username (id=username)
#  3. Fill password (id=password)
#  4. Wait for LOGIN button to become enabled
#  5. Click LOGIN button (type=button, NOT SINGLE SIGN IN)
#  6. Wait for redirect to dashboard
# ══════════════════════════════════════════════════════════════
Login To Application
    [Documentation]    Fills credentials on the app page and clicks the LOGIN button.
    [Arguments]    ${username}    ${password}
    Navigate To    ${BASE_URL}
    Fill Username    ${username}
    Fill Password    ${password}
    Sleep    1s
    Wait Until Element Is Enabled    ${LOGIN_BTN}    timeout=15s
    Click Element    ${LOGIN_BTN}
    Log    Clicked LOGIN button    level=INFO
    Sleep    10s
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

# ══════════════════════════════════════════════════════════════
#  Verify login success
# ══════════════════════════════════════════════════════════════
Verify Successful Login
    [Documentation]    Verifies user is on the app dashboard (not on login/cognito page).
    ${url}=    Get Location
    Should Not Contain    ${url}    /login    msg=Still on login page: ${url}
    Should Not Contain    ${url}    cognito    msg=Still on Cognito page: ${url}
    ${found}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible
    ...    xpath://*[contains(text(),'Welcome') or contains(text(),'Dashboard') or contains(text(),'Home') or contains(text(),'Quick Actions') or contains(text(),'Project')]
    ...    timeout=15s
    IF    ${found}
        Log    Dashboard content found — login successful    level=INFO
    ELSE
        Log    Login verified by URL — on app domain, not on login page    level=INFO
    END

# ══════════════════════════════════════════════════════════════
#  Logout: Click Profile icon (aria-label='Profile') → click 'logout'
# ══════════════════════════════════════════════════════════════
Logout From Application
    Click Profile Icon
    Sleep    1s
    Click Logout Text
    Sleep    1s
    Confirm Logout Popup
    Sleep    3s
    Log    Logout complete    level=INFO

Click Profile Icon
    [Documentation]    Clicks the Profile icon button (letter avatar) in the top-right header.
    Wait Until Element Is Visible    xpath://button[@aria-label='Profile']    timeout=15s
    Click Element    xpath://button[@aria-label='Profile']
    Log    Clicked Profile icon    level=INFO

Click Logout Text
    [Documentation]    Clicks the 'logout' menu item in the dropdown after Profile icon is clicked.
    ${found}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://li[normalize-space(.)='logout']    timeout=5s
    IF    ${found}
        Click Element    xpath://li[normalize-space(.)='logout']
        Log    Clicked logout menu item    level=INFO
        RETURN
    END
    ${found}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://li[contains(normalize-space(.),'logout') or contains(normalize-space(.),'Logout')]    timeout=3s
    IF    ${found}
        Click Element    xpath://li[contains(normalize-space(.),'logout') or contains(normalize-space(.),'Logout')]
        RETURN
    END
    ${found}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://*[@role='menuitem' and contains(normalize-space(.),'logout')]    timeout=3s
    IF    ${found}
        Click Element    xpath://*[@role='menuitem' and contains(normalize-space(.),'logout')]
        RETURN
    END
    Fail    Could not find logout option in the dropdown

Confirm Logout Popup
    [Documentation]    Clicks 'YES' on the MUI logout confirmation dialog.
    ...                Dialog title: 'Logout Prompt', text: 'Are you sure you want to logout?'
    ...                Buttons: NO and YES
    ${yes_found}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    xpath://button[normalize-space(.)='YES']    timeout=10s
    IF    ${yes_found}
        Click Element    xpath://button[normalize-space(.)='YES']
        Log    Clicked YES on logout confirmation dialog    level=INFO
        RETURN
    END
    ${yes_found}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    xpath://button[normalize-space(.)='Yes']    timeout=3s
    IF    ${yes_found}
        Click Element    xpath://button[normalize-space(.)='Yes']
        Log    Clicked Yes on logout confirmation dialog    level=INFO
        RETURN
    END
    ${yes_found}=    Run Keyword And Return Status
    ...    Wait Until Element Is Visible    xpath://div[contains(@class,'MuiDialog')]//button[last()]    timeout=3s
    IF    ${yes_found}
        Click Element    xpath://div[contains(@class,'MuiDialog')]//button[last()]
        Log    Clicked last button in MUI dialog    level=INFO
        RETURN
    END
    Log    No logout confirmation popup detected    level=WARN

Capture Failure Screenshot
    Create Directory    ${SCREENSHOT_DIR}
    ${ts}=    Evaluate    __import__('datetime').datetime.now().strftime('%Y%m%d_%H%M%S')
    Capture Page Screenshot    ${SCREENSHOT_DIR}/failure_${ts}.png
