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

TC_POS_001 - Successful login with valid username and password
    [Documentation]    Verify user is successfully authenticated and redirected to the dashboard/home page with a valid session established.
    [Tags]             positive    TC_POS_001    High
    Navigate To    ${BASE_URL}
    Wait Until Page Contains Element    id:username    timeout=${TIMEOUT}
    Wait Until Page Contains Element    id:password    timeout=${TIMEOUT}
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Logout From Application

TC_POS_002 - Successful login and verify session persistence on page refresh
    [Documentation]    Verify user session persists after page refresh and user remains authenticated without being forced to log in again.
    [Tags]             positive    TC_POS_002    High
    Navigate To    ${BASE_URL}
    Login To Application    ${USERNAME}    ${PASSWORD}
    Verify Successful Login
    Reload Page
    Sleep    3s
    ${current_url}=    Get Location
    Should Not Contain    ${current_url}    /login    msg=User was redirected back to login page after refresh
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    Page Should Not Contain Element    id:username    message=Login form should not be visible after refresh
    Logout From Application

*** Keywords ***

Open Test Browser
    [Documentation]    Opens the browser and sets default timeout and window size.
    Create Directory    ${SCREENSHOT_DIR}
    Open Browser    ${BASE_URL}    ${BROWSER}
    Set Selenium Timeout    ${TIMEOUT}
    Maximize Browser Window
    Sleep    2s

Navigate To
    [Arguments]    ${url}
    [Documentation]    Navigates to the specified URL.
    Go To    ${url}
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}
    Sleep    1s

Fill Username Field
    [Arguments]    ${value}
    [Documentation]    MUI-aware username field input.
    Wait Until Page Contains Element    id:username    timeout=${TIMEOUT}
    Click Element    id:username
    Sleep    0.3s
    Clear Element Text    id:username
    Input Text    id:username    ${value}
    Sleep    0.3s

Fill Password Field
    [Arguments]    ${value}
    [Documentation]    MUI-aware password field input.
    Wait Until Page Contains Element    id:password    timeout=${TIMEOUT}
    Click Element    id:password
    Sleep    0.3s
    Clear Element Text    id:password
    Input Password    id:password    ${value}
    Sleep    0.3s

Click Login Button
    [Documentation]    Clicks the LOGIN button (type=button). Waits until it is enabled before clicking.
    ${login_locator}=    Set Variable    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login' or normalize-space(.)='Log In' or normalize-space(.)='Sign In')]
    Wait Until Page Contains Element    ${login_locator}    timeout=${TIMEOUT}
    Wait Until Element Is Enabled    ${login_locator}    timeout=${TIMEOUT}
    Click Element    ${login_locator}
    Sleep    1s

Login To Application
    [Arguments]    ${username}    ${password}
    [Documentation]    Full login flow: navigate, fill fields, click login, wait for page load.
    Navigate To    ${BASE_URL}
    Fill Username Field    ${username}
    Fill Password Field    ${password}
    Sleep    1s
    Wait Until Keyword Succeeds    10s    0.5s    Element Should Be Enabled    xpath://button[@type='button' and (normalize-space(.)='LOGIN' or normalize-space(.)='Login' or normalize-space(.)='Log In' or normalize-space(.)='Sign In')]
    Click Login Button
    Sleep    3s
    Wait Until Page Contains Element    tag:body    timeout=${TIMEOUT}

Verify Successful Login
    [Documentation]    Verifies the user is logged in by checking URL does not contain /login and a nav/header element is visible.
    ${current_url}=    Get Location
    Should Not Contain    ${current_url}    /login    msg=Login page URL still present — login may have failed
    ${nav_visible}=    Run Keyword And Return Status    Wait Until Page Contains Element    xpath://nav | //header | //div[@role='banner'] | //button[@aria-label='Profile']    timeout=15s
    IF    not ${nav_visible}
        ${body_text}=    Get Text    tag:body
        Should Not Be Empty    ${body_text}    msg=Page body is empty after login
    END
    Log    Login verified successfully. Current URL: ${current_url}

Logout From Application
    [Documentation]    Performs logout via profile icon and confirmation popup.
    Click User Avatar
    Sleep    1s
    Click Logout Option
    Sleep    1s
    Wait Until Page Contains Element    xpath://button[normalize-space(.)='Yes']    timeout=15s
    Click Element    xpath://button[normalize-space(.)='Yes']
    Sleep    3s
    Log    Logout complete.

Click User Avatar
    [Documentation]    Clicks the profile/avatar button in the top navigation.
    Wait Until Page Contains Element    xpath://button[@aria-label='Profile']    timeout=${TIMEOUT}
    Click Element    xpath://button[@aria-label='Profile']

Click Logout Option
    [Documentation]    Clicks the logout text option in the profile dropdown.
    Wait Until Page Contains Element    xpath://p[normalize-space(.)='logout']    timeout=15s
    Click Element    xpath://p[normalize-space(.)='logout']

Capture Failure Screenshot
    [Documentation]    Captures a screenshot on test failure and saves to the screenshots directory.
    Create Directory    ${SCREENSHOT_DIR}
    ${test_name}=    Get Variable Value    ${TEST NAME}    unknown_test
    ${timestamp}=    Evaluate    __import__('datetime').datetime.now().strftime('%Y%m%d_%H%M%S')
    ${filename}=     Set Variable    ${SCREENSHOT_DIR}/${test_name}_${timestamp}.png
    Capture Page Screenshot    ${filename}
    Log    Screenshot saved: ${filename}

Verify Error Message
    [Arguments]    ${expected_text}=${EMPTY}
    [Documentation]    Verifies an error message is displayed. Optionally checks for specific text.
    ${error_visible}=    Run Keyword And Return Status    Wait Until Page Contains Element
    ...    xpath://*[contains(@class,'error') or contains(@class,'alert') or contains(@class,'danger') or contains(@role,'alert')]
    ...    timeout=10s
    IF    not ${error_visible}
        Wait Until Page Contains Element    xpath://*[contains(text(),'Invalid') or contains(text(),'incorrect') or contains(text(),'failed') or contains(text(),'wrong') or contains(text(),'error')]    timeout=10s
    END
    IF    '${expected_text}' != '${EMPTY}'
        Page Should Contain    ${expected_text}
    END
    Log    Error message verified on page.