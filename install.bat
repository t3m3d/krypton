@echo off
echo Installing kcc...
copy "%~dp0versions\kcc_v101.exe" "%SystemRoot%\System32\kcc.exe" >nul
if errorlevel 1 (
    echo ERROR: Failed to install. Try running as Administrator.
    pause
    exit /b 1
)
echo Done! You can now run: kcc yourfile.k
pause
