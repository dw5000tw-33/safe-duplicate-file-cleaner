@echo off
setlocal

set "DFC_SCRIPT=%~dp0checker.ps1"
set "DFC_LOG=%TEMP%\duplicate_file_checker_error.txt"

if not exist "%DFC_SCRIPT%" (
    echo checker.ps1 was not found. Please extract the whole ZIP file first.
    pause
    exit /b 1
)

if exist "%DFC_LOG%" del /q "%DFC_LOG%" >nul 2>nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%DFC_SCRIPT%" 2> "%DFC_LOG%"
set "DFC_EXIT=%ERRORLEVEL%"

if not "%DFC_EXIT%"=="0" (
    chcp 65001 >nul
    echo.
    echo The tool could not start. The error is shown below:
    echo.
    if exist "%DFC_LOG%" type "%DFC_LOG%"
    echo.
    echo Please take a screenshot of this window.
    pause
)

exit /b %DFC_EXIT%

