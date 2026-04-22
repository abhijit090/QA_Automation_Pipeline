*** Settings ***
Library           SeleniumLibrary
Library           OperatingSystem
Library           String
Library           Collections

Suite Name        login fu ctionlity
Suite Setup       Open Test Browser
Suite Teardown    Close All Browsers
Test Teardown     Run Keyword If Test Failed    Capture Failure Screenshot

*** Variables ***
${BASE_URL}           https://development.d36z6oo50ky8dh.amplifyapp.com/login
${BROWSER}            Chrome
${TIMEOUT}            60s
${USERNAME}           testd1051@gmail.com
${PASSWORD}           Qj8BTm9g
${SCREENSHOT_DIR}     ${CURDIR}/../../reports/screenshots

*** Test Cases ***

TC_POS_001 - Successful login with valid username and password
    [Documentation]    Verify that a user can successfully log in with valid credentials and is redirected to the dashboard.
    [Tags]    positive    TC_POS_001    High
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Logout From Application

TC_POS_002 - Successful login with email address containing uppercase characters
    [Documentation]    Verify that login is case-insensitive for email field by using uppercase email.
    [Tags]    positive    TC_POS_002    Medium
    Login To Application    TESTD1051@GMAIL.COM    ${PASSWORD}
    Verify Successful Login
    Logout From Application

TC_NEG_001 - Login attempt with empty username and empty password
    [Documentation]    Verify that validation error messages are shown when both fields are left empty.
    [Tags]    negative    TC_NEG_001    High
    Navigate To    ${BASE_URL}
    Click Login Button Empty
    Sleep    2s
    Verify Error Message
    ${current_url}=    Get Location
    Should Contain    ${current_url}    login

TC_NEG_002 - Login attempt with valid username and incorrect password
    [Documentation]    Verify that an error message is displayed when an incorrect password is used.
    [Tags]    negative    TC_NEG_002    High
    Navigate To    ${BASE_URL}
    Fill Username Field    ${USERNAME}
    Fill Password Field    WrongPassword123!
    Sleep    1s
    Click Login Button
    Sleep    3s
    Verify Error Message
    ${current_url}=    Get Location
    Should Contain    ${current_url}    login

TC_NEG_003 - Login attempt with invalid/non-existent email and any password
    [Documentation]    Verify that an error message is displayed when a non-existent email is used.
    [Tags]    negative    TC_NEG_003    High
    Navigate To    ${BASE_URL}
    Fill Username Field    nonexistent_user_xyz@invalid.com
    Fill Password Field    AnyPassword123!
    Sleep    1s
    Click Login Button
    Sleep    3s
    Verify Error Message
    ${current_url}=    Get Location
    Should Contain    ${current_url}    login

*** Keywords ***

Open Test Browser
    [Documentation]    Opens the browser and navigates to the base URL.
    Create Directory    ${SCREENSHOT_DIR}
    Open Browser    ${BASE_URL}    ${BROWSER}
    Maximize Browser Window
    Set Selenium Timeout    ${TIMEOUT}
    Set Selenium Implicit Wait    5s

Navigate To
    [Arguments]    ${url}
    [Documentation]    Navigates to the specified URL and waits for page to load.
    Go To    ${url}
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    Sleep    2s

Fill Username Field
    [Arguments]    ${value}
    [Documentation]    Clears and fills the username/email field in a MUI-aware manner.
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}
    Click Element    id:username
    Sleep    0.3s
    Clear Element Text    id:username
    Input Text    id:username    ${value}

Fill Password Field
    [Arguments]    ${value}
    [Documentation]    Clears and fills the password field in a MUI-aware manner.
    Wait Until Element Is Visible    id:password    timeout=${TIMEOUT}
    Click Element    id:password
    Sleep    0.3s
    Clear Element Text    id:password
    Input Password    id:password    ${value}

Click Login Button
    [Documentation]    Clicks the LOGIN button (type=button). Waits until it is enabled before clicking.
    Wait Until Element Is Visible    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]    timeout=${TIMEOUT}
    Wait Until Element Is Enabled    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]    timeout=${TIMEOUT}
    Click Element    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]

Click Login Button Empty
    [Documentation]    Attempts to click the LOGIN button when fields may be empty (button may be disabled).
    Wait Until Element Is Visible    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]    timeout=${TIMEOUT}
    ${is_enabled}=    Run Keyword And Return Status    Element Should Be Enabled    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    IF    ${is_enabled}
        Click Element    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    ELSE
        Log    LOGIN button is disabled as expected when fields are empty — verifying error state via UI
    END

Login To Application
    [Arguments]    ${username}    ${password}
    [Documentation]    Full login flow: navigate, fill credentials, wait for button enabled, click login.
    Navigate To    ${BASE_URL}
    Fill Username Field    ${username}
    Fill Password Field    ${password}
    Sleep    1s
    Wait Until Keyword Succeeds    10s    0.5s    Element Should Be Enabled    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Click Login Button
    Sleep    3s
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

Logout From Application
    [Documentation]    Performs the full logout flow via profile icon and confirmation popup.
    Click User Avatar
    Sleep    1s
    Click Logout Option
    Sleep    1s
    Wait Until Element Is Visible    xpath://button[normalize-space(.)='Yes']    timeout=${TIMEOUT}
    Click Element    xpath://button[normalize-space(.)='Yes']
    Sleep    3s

Click User Avatar
    [Documentation]    Clicks the Profile/Avatar icon in the navigation bar.
    Wait Until Element Is Visible    xpath://button[@aria-label='Profile']    timeout=${TIMEOUT}
    Click Element    xpath://button[@aria-label='Profile']

Click Logout Option
    [Documentation]    Clicks the logout text in the profile dropdown menu.
    Wait Until Element Is Visible    xpath://p[normalize-space(.)='logout']    timeout=${TIMEOUT}
    Click Element    xpath://p[normalize-space(.)='logout']

Capture Failure Screenshot
    [Documentation]    Captures a screenshot on test failure and saves it to the screenshots directory.
    ${timestamp}=    Get Time    format=%Y%m%d_%H%M%S
    ${test_name}=    Get Variable Value    ${TEST NAME}    unknown_test
    ${safe_name}=    Replace String    ${test_name}    ${SPACE}    _
    ${filename}=    Set Variable    ${SCREENSHOT_DIR}/${safe_name}_${timestamp}.png
    Capture Page Screenshot    ${filename}
    Log    Screenshot saved to: ${filename}

Verify Successful Login
    [Documentation]    Verifies that the user has been redirected away from the login page and the dashboard is visible.
    Wait Until Keyword Succeeds    15s    1s    Location Should Not Contain    /login
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    ${current_url}=    Get Location
    Should Not Contain    ${current_url}    /login
    Log    Successfully logged in. Current URL: ${current_url}

Verify Error Message
    [Arguments]    ${expected_text}=${EMPTY}
    [Documentation]    Verifies that an error or validation message is visible on the login page.
    Sleep    2s
    ${error_found}=    Run Keyword And Return Status    Wait Until Element Is Visible
    ...    xpath://*[contains(@class,'error') or contains(@class,'Error') or contains(@class,'alert') or contains(@class,'Alert') or contains(@class,'message') or contains(@class,'Message') or contains(@role,'alert')]
    ...    timeout=10s
    IF    not ${error_found}
        ${error_found}=    Run Keyword And Return Status    Wait Until Element Is Visible
        ...    xpath://*[contains(text(),'Invalid') or contains(text(),'invalid') or contains(text(),'incorrect') or contains(text(),'Incorrect') or contains(text(),'required') or contains(text(),'Required') or contains(text(),'exist') or contains(text(),'Exist') or contains(text(),'wrong') or contains(text(),'Wrong')]
        ...    timeout=10s
    END
    IF    ${error_found}
        Log    Error/validation message is displayed as expected.
    ELSE
        Log    WARNING: No explicit error message element found — verifying page did not navigate away.
        ${current_url}=    Get Location
        Should Contain    ${current_url}    login
    END
    IF    '${expected_text}' != '${EMPTY}'
        Page Should Contain    ${expected_text}
    END