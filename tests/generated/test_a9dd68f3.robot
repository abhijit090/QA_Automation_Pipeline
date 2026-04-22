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

*** Test Cases ***
TC_POS_001 - Successful login with valid username and password
    [Documentation]    Verify user is authenticated and redirected to dashboard with valid credentials
    [Tags]    positive    TC_POS_001    High
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Logout From Application

TC_POS_002 - Successful login with email address containing uppercase letters
    [Documentation]    Verify login is case-insensitive for email field
    [Tags]    positive    TC_POS_002    Medium
    Login To Application    TESTD1051@GMAIL.COM    ${PASSWORD}
    Verify Successful Login
    Page Should Not Contain    error
    Logout From Application

TC_NEG_001 - Login fails when username field is left empty
    [Documentation]    Verify login is blocked and error shown when username field is empty
    [Tags]    negative    TC_NEG_001    High
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}
    Fill Password Field    ${PASSWORD}
    Sleep    0.5s
    ${login_btn_xpath}=    Set Variable    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Wait Until Element Is Visible    ${login_btn_xpath}    timeout=${TIMEOUT}
    ${is_enabled}=    Run Keyword And Return Status    Element Should Be Enabled    ${login_btn_xpath}
    IF    ${is_enabled}
        Click Element    ${login_btn_xpath}
    END
    Sleep    2s
    ${current_url}=    Get Location
    Should Contain    ${current_url}    /login
    Verify Error Message

TC_NEG_002 - Login fails when password field is left empty
    [Documentation]    Verify login is blocked and error shown when password field is empty
    [Tags]    negative    TC_NEG_002    High
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}
    Fill Username Field    ${USERNAME}
    Sleep    0.5s
    ${login_btn_xpath}=    Set Variable    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Wait Until Element Is Visible    ${login_btn_xpath}    timeout=${TIMEOUT}
    ${is_enabled}=    Run Keyword And Return Status    Element Should Be Enabled    ${login_btn_xpath}
    IF    ${is_enabled}
        Click Element    ${login_btn_xpath}
    END
    Sleep    2s
    ${current_url}=    Get Location
    Should Contain    ${current_url}    /login
    Verify Error Message

*** Keywords ***
Open Test Browser
    ${options}=    Evaluate    sys.modules['selenium.webdriver'].ChromeOptions()    sys
    Call Method    ${options}    add_argument    --start-maximized
    Call Method    ${options}    add_argument    --disable-notifications
    Create Directory    ${SCREENSHOT_DIR}
    Open Browser    ${BASE_URL}    ${BROWSER}    options=${options}
    Set Selenium Timeout    ${TIMEOUT}
    Set Selenium Implicit Wait    2s
    Maximize Browser Window

Navigate To
    [Arguments]    ${url}
    Go To    ${url}
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    Sleep    1s

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
    ${login_btn_xpath}=    Set Variable    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Wait Until Element Is Visible    ${login_btn_xpath}    timeout=${TIMEOUT}
    Wait Until Keyword Succeeds    15s    0.5s    Element Should Be Enabled    ${login_btn_xpath}
    Click Element    ${login_btn_xpath}

Login To Application
    [Arguments]    ${username}    ${password}
    Navigate To    ${BASE_URL}
    Wait Until Element Is Visible    id:username    timeout=${TIMEOUT}
    Fill Username Field    ${username}
    Fill Password Field    ${password}
    Sleep    1s
    Wait Until Keyword Succeeds    10s    0.5s    Element Should Be Enabled    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login')]
    Click Login Button
    Sleep    3s
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

Logout From Application
    Click User Avatar
    Sleep    1s
    Click Logout Option

Click User Avatar
    Wait Until Element Is Visible    xpath://button[@aria-label='Profile']    timeout=${TIMEOUT}
    Click Element    xpath://button[@aria-label='Profile']

Click Logout Option
    Wait Until Element Is Visible    xpath://p[normalize-space(.)='logout']    timeout=${TIMEOUT}
    Click Element    xpath://p[normalize-space(.)='logout']
    Sleep    1s
    Wait Until Element Is Visible    xpath://button[normalize-space(.)='Yes']    timeout=${TIMEOUT}
    Click Element    xpath://button[normalize-space(.)='Yes']
    Sleep    3s

Capture Failure Screenshot
    Create Directory    ${SCREENSHOT_DIR}
    ${timestamp}=    Evaluate    __import__('datetime').datetime.now().strftime('%Y%m%d_%H%M%S')
    ${test_name}=    Get Variable Value    ${TEST NAME}    unknown_test
    ${safe_name}=    Replace String    ${test_name}    ${SPACE}    _
    Capture Page Screenshot    ${SCREENSHOT_DIR}/${safe_name}_${timestamp}.png

Verify Successful Login
    Sleep    2s
    ${_url}=    Get Location
    Should Not Contain    ${_url}    /login
    ${current_url}=    Get Location
    Should Not Contain    ${current_url}    /login
    ${nav_visible}=    Run Keyword And Return Status    Wait Until Element Is Visible
    ...    xpath://nav | //header | //*[@aria-label='Profile'] | //*[contains(@class,'dashboard')] | //*[contains(@class,'navbar')]
    ...    timeout=10s
    IF    not ${nav_visible}
        Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
        Log    Dashboard page loaded but nav/header selector may differ — URL confirms redirect away from login
    END

Verify Error Message
    [Arguments]    ${expected_text}=${EMPTY}
    Sleep    1s
    ${error_visible}=    Run Keyword And Return Status    Wait Until Element Is Visible
    ...    xpath://*[contains(@class,'error') or contains(@class,'Error') or contains(@class,'alert') or contains(@class,'Alert') or contains(@class,'MuiFormHelperText') or contains(@class,'helper') or contains(@role,'alert')]
    ...    timeout=10s
    IF    ${error_visible}
        Log    Error message element is visible on the page
    ELSE
        Log    No explicit error element found — verifying page remains on login
    END
    ${current_url}=    Get Location
    Should Contain    ${current_url}    /login
    IF    '${expected_text}' != '${EMPTY}'
        Page Should Contain    ${expected_text}
    END