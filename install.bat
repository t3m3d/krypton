@echo off
setlocal enabledelayedexpansion

set INSTALL_DIR=C:\krypton

REM ── Find latest kcc_v*.exe by date ──────────────────────────
set LATEST=
for /f "delims=" %%F in ('dir /b /o-d versions\kcc_v*.exe 2^>nul') do (
    if "!LATEST!"=="" set LATEST=%%F
)

if "!LATEST!"=="" (
    echo ERROR: No kcc_v*.exe found in versions\
    pause & exit /b 1
)

REM ── Derive version string from filename (kcc_v118.exe -> 1.1.8) ──
set RAW=!LATEST!
set RAW=!RAW:kcc_v=!
set RAW=!RAW:.exe=!
set V1=!RAW:~0,1!
set V2=!RAW:~1,1!
set V3=!RAW:~2,1!
set NEW_VER=!V1!.!V2!.!V3!

REM ── Read currently installed version ────────────────────────
set OLD_VER=none
if exist "%INSTALL_DIR%\version.txt" (
    set /p OLD_VER=<"%INSTALL_DIR%\version.txt"
)

if "!OLD_VER!"=="!NEW_VER!" (
    echo Already on v!NEW_VER! -- nothing to do.
    pause & exit /b 0
)

echo Upgrading kcc  !OLD_VER!  ^>  !NEW_VER!

REM ── Create directories ───────────────────────────────────────
if not exist "%INSTALL_DIR%\bin"     mkdir "%INSTALL_DIR%\bin"
if not exist "%INSTALL_DIR%\headers" mkdir "%INSTALL_DIR%\headers"

REM ── Copy binary ──────────────────────────────────────────────
copy /Y "versions\!LATEST!" "%INSTALL_DIR%\bin\kcc.exe" >nul
if errorlevel 1 ( echo FAILED: copy kcc.exe & pause & exit /b 1 )

REM ── Copy kcc.sh driver ───────────────────────────────────────
copy /Y "kcc.sh" "%INSTALL_DIR%\bin\kcc.sh" >nul
if errorlevel 1 ( echo FAILED: copy kcc.sh & pause & exit /b 1 )

REM ── Copy headers ─────────────────────────────────────────────
xcopy /Y /E /Q "headers\*" "%INSTALL_DIR%\headers\" >nul
if errorlevel 1 ( echo FAILED: copy headers & pause & exit /b 1 )

REM ── Write version.txt ────────────────────────────────────────
echo !NEW_VER!>"%INSTALL_DIR%\version.txt"

REM ── Append to version_history.txt ───────────────────────────
for /f "tokens=1-3 delims=/ " %%A in ("%DATE%") do set TODAY=%%C-%%A-%%B
for /f "tokens=1-2 delims=: " %%A in ("%TIME: =0%") do set NOW=%%A:%%B
echo !TODAY! !NOW!  !OLD_VER! -> !NEW_VER!  (!LATEST!)>>"%INSTALL_DIR%\version_history.txt"

echo.
echo ============================================================
echo  Installed:  v!NEW_VER!  ^(!LATEST!^)
echo  Location:   %INSTALL_DIR%\bin\kcc.exe
echo  Headers:    %INSTALL_DIR%\headers\
echo.
echo  Previous version: !OLD_VER!
echo  History log:      %INSTALL_DIR%\version_history.txt
echo.
if "!OLD_VER!"=="none" (
    echo  First install -- add to PATH:
    echo    Admin cmd:   setx /M PATH "%%PATH%%;C:\krypton\bin"
    echo    .bashrc:     export PATH="/c/krypton/bin:$PATH"
)
echo ============================================================
echo.
pause
endlocal
