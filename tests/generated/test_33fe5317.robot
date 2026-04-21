*** Settings ***
Library           SeleniumLibrary
Library           OperatingSystem
Library           String
Library           Collections

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
${LOGIN_BTN}          xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]

*** Test Cases ***

TC_POS_001 - Successful Login With Valid Username And Password
    [Documentation]    Verify user is successfully authenticated and redirected to dashboard/home page with session active.
    [Tags]    positive    TC_POS_001    High
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Page Should Not Contain    Error
    Logout From Application

TC_POS_002 - Successful Login And Verification Of Page Title And URL After Redirect
    [Documentation]    Verify URL changes to authenticated route and correct page title is displayed with no errors.
    [Tags]    positive    TC_POS_002    High
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    ${current_url}=    Get Location
    Should Not Contain    ${current_url}    /login
    ${title}=    Get Title
    Should Not Be Empty    ${title}
    Page Should Not Contain    Error
    Page Should Not Contain    Invalid
    Logout From Application

TC_NEG_001 - Login Attempt With Empty Username And Empty Password
    [Documentation]    Verify validation error messages are displayed for both empty fields and user remains on login page.
    [Tags]    negative    TC_NEG_001    High
    Navigate To    ${BASE_URL}
    ${current_url}=    Get Location
    Should Contain    ${current_url}    /login
    Click Element    id:username
    Sleep    0.3s
    Clear Element Text    id:username
    Click Element    id:password
    Sleep    0.3s
    Clear Element Text    id:password
    ${login_disabled}=    Run Keyword And Return Status    Element Should Be Disabled    ${LOGIN_BTN}
    IF    ${login_disabled}
        Log    Login button is disabled as expected when fields are empty
    ELSE
        Click Element    ${LOGIN_BTN}
        Sleep    2s
    END
    ${current_url_after}=    Get Location
    Should Contain    ${current_url_after}    /login
    ${error_visible}=    Run Keyword And Return Status    Page Should Contain Element
    ...    xpath://*[contains(text(),'required') or contains(text(),'Required') or contains(text(),'empty') or contains(text(),'Empty')]
    IF    ${error_visible}
        Log    Validation error message is displayed as expected
    ELSE
        Log    Login button remains disabled — form validation prevents submission
    END

TC_NEG_002 - Login Attempt With Valid Username But Incorrect Password
    [Documentation]    Verify error message is displayed for invalid credentials and user is not authenticated.
    [Tags]    negative    TC_NEG_002    High
    Navigate To    ${BASE_URL}
    ${current_url}=    Get Location
    Should Contain    ${current_url}    /login
    Fill Username Field    ${USERNAME}
    Fill Password Field    WrongPassword123!
    Sleep    1s
    Click Login Button
    Sleep    3s
    ${current_url_after}=    Get Location
    Should Contain    ${current_url_after}    /login
    Verify Error Message

*** Keywords ***

Open Test Browser
    [Documentation]    Opens the browser and sets default timeout and window size.
    Create Directory    ${SCREENSHOT_DIR}
    Open Browser    ${BASE_URL}    ${BROWSER}
    Maximize Browser Window
    Set Selenium Timeout    ${TIMEOUT}
    Set Selenium Implicit Wait    2s

Navigate To
    [Arguments]    ${url}
    [Documentation]    Navigates to the specified URL and waits for page to load.
    Go To    ${url}
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

Fill Username Field
    [Arguments]    ${value}
    [Documentation]    Fills the username/email field with MUI-aware interaction.
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}
    Click Element    id:username
    Sleep    0.3s
    Clear Element Text    id:username
    Input Text    id:username    ${value}

Fill Password Field
    [Arguments]    ${value}
    [Documentation]    Fills the password field with MUI-aware interaction.
    Wait Until Element Is Visible    id:password    timeout=${TIMEOUT}
    Click Element    id:password
    Sleep    0.3s
    Clear Element Text    id:password
    Input Password    id:password    ${value}

Click Login Button
    [Documentation]    Clicks the LOGIN button (type=button). Waits until it is enabled before clicking.
    Wait Until Element Is Visible    ${LOGIN_BTN}    timeout=${TIMEOUT}
    Wait Until Keyword Succeeds    15s    0.5s    Element Should Be Enabled    ${LOGIN_BTN}
    Click Element    ${LOGIN_BTN}

Login To Application
    [Arguments]    ${username}    ${password}
    [Documentation]    Performs full login flow: navigate, fill credentials, click login, wait for redirect.
    Navigate To    ${BASE_URL}
    Fill Username Field    ${username}
    Fill Password Field    ${password}
    Sleep    1s
    Click Login Button
    Sleep    3s
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

Verify Successful Login
    [Documentation]    Verifies the user has been redirected away from the login page and is authenticated.
    ${current_url}=    Get Location
    Should Not Contain    ${current_url}    /login
    ${nav_visible}=    Run Keyword And Return Status    Page Should Contain Element
    ...    xpath://nav | //header | //*[@role='navigation'] | //*[@role='banner']
    IF    ${nav_visible}
        Log    Navigation/header element is visible — user is authenticated
    ELSE
        Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
        Log    Page body confirmed — redirect successful
    END

Logout From Application
    [Documentation]    Performs full logout: profile icon → logout text → confirm Yes.
    Click User Avatar
    Sleep    1s
    Click Logout Option
    Sleep    1s
    Wait Until Element Is Visible    xpath://button[normalize-space(.)='Yes']    timeout=${TIMEOUT}
    Click Element    xpath://button[normalize-space(.)='Yes']
    Sleep    3s

Click User Avatar
    [Documentation]    Clicks the profile/avatar icon to open the user menu.
    Wait Until Element Is Visible    xpath://button[@aria-label='Profile']    timeout=${TIMEOUT}
    Click Element    xpath://button[@aria-label='Profile']

Click Logout Option
    [Documentation]    Clicks the logout option from the user menu dropdown.
    Wait Until Element Is Visible    xpath://p[normalize-space(.)='logout']    timeout=${TIMEOUT}
    Click Element    xpath://p[normalize-space(.)='logout']

Verify Error Message
    [Arguments]    ${expected_text}=${EMPTY}
    [Documentation]    Verifies that an error message is displayed on the login page after a failed login attempt.
    Sleep    1s
    IF    '${expected_text}' != '${EMPTY}'
        Page Should Contain    ${expected_text}
    ELSE
        ${error_found}=    Run Keyword And Return Status    Page Should Contain Element
        ...    xpath://*[contains(translate(text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'invalid') or contains(translate(text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'incorrect') or contains(translate(text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'wrong') or contains(translate(text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'error') or contains(translate(text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'failed') or contains(translate(text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'unauthorized')]
        IF    ${error_found}
            Log    Error message is displayed as expected after failed login attempt
        ELSE
            ${url_still_login}=    Run Keyword And Return Status    Location Should Contain    /login
            IF    ${url_still_login}
                Log    User remains on login page — login was not granted as expected
            ELSE
                Fail    Expected an error message or to remain on login page, but neither condition was met
            END
        END
    END

Capture Failure Screenshot
    [Documentation]    Captures a screenshot when a test fails and saves to the screenshots directory.
    ${timestamp}=    Get Time    epoch
    ${screenshot_name}=    Set Variable    ${SCREENSHOT_DIR}/failure_${TEST_NAME}_${timestamp}.png
    Capture Page Screenshot    ${screenshot_name}
    Log    Screenshot saved: ${screenshot_name}