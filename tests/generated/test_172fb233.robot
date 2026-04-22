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

*** Test Cases ***

TC_POS_001 - Successful Login With Valid Username And Password
    [Documentation]    Verify user is successfully authenticated and redirected to dashboard/home page with session established.
    [Tags]    positive    TC_POS_001    High
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Logout From Application

TC_POS_002 - Login Page Renders All Required UI Elements Correctly
    [Documentation]    Verify all login page UI elements are correctly rendered and accessible before any interaction.
    [Tags]    positive    TC_POS_002    Medium
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}
    Element Should Be Visible    id:username
    Element Should Be Visible    id:password
    ${pwd_type}=    Get Element Attribute    id:password    type
    Should Be Equal As Strings    ${pwd_type}    password
    Element Should Be Visible    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Element Should Be Visible    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    ${page_text}=    Get Text    tag:body
    ${has_heading}=    Run Keyword And Return Status    Page Should Contain Element    xpath://*[self::h1 or self::h2 or self::h3 or self::h4 or self::h5 or self::h6 or self::p][string-length(normalize-space(.)) > 0]
    Should Be True    ${has_heading}
    ${has_forgot}=    Run Keyword And Return Status    Page Should Contain Element    xpath://*[contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'forgot')]
    Log    Forgot Password link present: ${has_forgot}
    ${has_signup}=    Run Keyword And Return Status    Page Should Contain Element    xpath://*[contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'sign up') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'register') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'create account')]
    Log    Sign Up / Register link present: ${has_signup}

TC_NEG_001 - Login Attempt With Empty Username And Empty Password
    [Documentation]    Verify validation errors are displayed for both empty fields; login does not proceed.
    [Tags]    negative    TC_NEG_001    High
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}
    Click Element    id:username
    Sleep    0.3s
    Clear Element Text    id:username
    Click Element    id:password
    Sleep    0.3s
    Clear Element Text    id:password
    ${login_btn_xpath}=    Set Variable    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    ${btn_enabled}=    Run Keyword And Return Status    Element Should Be Enabled    ${login_btn_xpath}
    IF    ${btn_enabled}
        Click Element    ${login_btn_xpath}
        Sleep    2s
    END
    ${current_url}=    Get Location
    Should Contain    ${current_url}    /login
    ${has_email_error}=    Run Keyword And Return Status    Page Should Contain Element    xpath://*[contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'email is required') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'username is required') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'required')]
    ${has_pwd_error}=    Run Keyword And Return Status    Page Should Contain Element    xpath://*[contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'password is required') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'required')]
    Log    Email/Username validation error present: ${has_email_error}
    Log    Password validation error present: ${has_pwd_error}
    ${any_error}=    Evaluate    ${has_email_error} or ${has_pwd_error}
    Should Be True    ${any_error}    msg=Expected validation error messages for empty fields but none were found.

TC_NEG_002 - Login Attempt With Valid Username And Incorrect Password
    [Documentation]    Verify authentication error is displayed; user remains on login page and access is denied.
    [Tags]    negative    TC_NEG_002    High
    Navigate To    ${BASE_URL}
    Fill Username Field    ${USERNAME}
    Fill Password Field    WrongPassword123!
    Sleep    1s
    Wait Until Keyword Succeeds    10s    0.5s    Element Should Be Enabled    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Click Login Button
    Sleep    3s
    ${current_url}=    Get Location
    Should Contain    ${current_url}    /login
    Verify Error Message

*** Keywords ***

Open Test Browser
    [Documentation]    Opens the browser and maximises the window.
    Create Directory    ${SCREENSHOT_DIR}
    Open Browser    ${BASE_URL}    ${BROWSER}
    Maximize Browser Window
    Set Selenium Timeout    ${TIMEOUT}
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}

Navigate To
    [Arguments]    ${url}
    Go To    ${url}
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}

Fill Username Field
    [Arguments]    ${value}
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}
    Click Element    id:username
    Sleep    0.3s
    Clear Element Text    id:username
    Input Text    id:username    ${value}

Fill Password Field
    [Arguments]    ${value}
    Wait Until Element Is Visible    id:password    timeout=${TIMEOUT}
    Click Element    id:password
    Sleep    0.3s
    Clear Element Text    id:password
    Input Password    id:password    ${value}

Click Login Button
    [Documentation]    Clicks the LOGIN button (type=button). Waits until it is enabled before clicking.
    ${login_locator}=    Set Variable    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Wait Until Element Is Visible    ${login_locator}    timeout=${TIMEOUT}
    Wait Until Keyword Succeeds    15s    0.5s    Element Should Be Enabled    ${login_locator}
    Click Element    ${login_locator}

Login To Application
    [Arguments]    ${username}    ${password}
    Navigate To    ${BASE_URL}
    Fill Username Field    ${username}
    Fill Password Field    ${password}
    Sleep    1s
    Wait Until Keyword Succeeds    10s    0.5s    Element Should Be Enabled    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Click Login Button
    Sleep    3s
    Wait Until Page Contains Element    tag:body

Logout From Application
    [Documentation]    Performs full logout via profile icon → logout text → Yes confirmation.
    Click User Avatar
    Sleep    1s
    Click Logout Option
    Sleep    1s
    Wait Until Element Is Visible    xpath://button[normalize-space(.)='Yes']    timeout=15s
    Click Element    xpath://button[normalize-space(.)='Yes']
    Sleep    3s

Click User Avatar
    Wait Until Element Is Visible    xpath://button[@aria-label='Profile']    timeout=${TIMEOUT}
    Click Element    xpath://button[@aria-label='Profile']

Click Logout Option
    Wait Until Element Is Visible    xpath://p[normalize-space(.)='logout']    timeout=15s
    Click Element    xpath://p[normalize-space(.)='logout']

Capture Failure Screenshot
    [Documentation]    Captures a screenshot on test failure and saves it to the screenshots directory.
    Create Directory    ${SCREENSHOT_DIR}
    ${test_name_clean}=    Replace String    ${TEST NAME}    ${SPACE}    _
    ${timestamp}=    Get Time    epoch
    Capture Page Screenshot    ${SCREENSHOT_DIR}/${test_name_clean}_${timestamp}.png

Verify Successful Login
    [Documentation]    Verifies the user is redirected away from /login and a post-login UI element is visible.
    ${_url}=    Get Location
    Should Not Contain    ${_url}    /login
    ${url}=    Get Location
    Should Not Contain    ${url}    /login
    ${nav_visible}=    Run Keyword And Return Status    Wait Until Element Is Visible    xpath://nav | //header | //*[@role='navigation'] | //*[@role='banner']    timeout=10s
    IF    not ${nav_visible}
        Wait Until Element Is Visible    tag:body    timeout=10s
        ${body_text}=    Get Text    tag:body
        Should Not Be Empty    ${body_text}
    END

Verify Error Message
    [Arguments]    ${expected_text}=${EMPTY}
    [Documentation]    Verifies that an authentication error message is visible on the login page.
    ${error_xpath}=    Set Variable    xpath://*[contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'invalid') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'incorrect') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'wrong') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'failed') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'error') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'credentials') or contains(translate(normalize-space(.),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'denied')]
    ${error_found}=    Run Keyword And Return Status    Wait Until Element Is Visible    ${error_xpath}    timeout=10s
    IF    not ${error_found}
        ${page_source}=    Get Source
        ${source_lower}=    Convert To Lower Case    ${page_source}
        ${has_invalid}=    Run Keyword And Return Status    Should Contain    ${source_lower}    invalid
        ${has_incorrect}=    Run Keyword And Return Status    Should Contain    ${source_lower}    incorrect
        ${has_error}=    Run Keyword And Return Status    Should Contain    ${source_lower}    error
        ${any_found}=    Evaluate    ${has_invalid} or ${has_incorrect} or ${has_error}
        Should Be True    ${any_found}    msg=Expected an authentication error message but none was found on the page.
    END
    IF    '${expected_text}' != '${EMPTY}'
        Page Should Contain    ${expected_text}
    END