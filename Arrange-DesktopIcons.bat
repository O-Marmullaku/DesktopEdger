@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Arrange-DesktopIcons.ps1" %*
set "exitCode=%errorlevel%"
if not "%exitCode%"=="0" (
    echo.
    echo Desktop Edge Arranger failed with exit code %exitCode%.
    echo Press any key to close this window.
    pause >nul
)
exit /b %exitCode%
