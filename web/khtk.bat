@echo off
:: khtk.bat — build a .htk web app on Windows
:: Usage: khtk app.htk [-o app.exe] [--run]
setlocal

set INPUT=
set OUTPUT=
set RUN=0
set TMP=%TEMP%\khtk_%RANDOM%.c

:parse
if "%~1"=="" goto check
if "%~1"=="-o"    ( set OUTPUT=%~2& shift & shift & goto parse )
if "%~1"=="--run" ( set RUN=1& shift & goto parse )
if "%~1"=="-r"    ( set RUN=1& shift & goto parse )
set INPUT=%~1
shift
goto parse

:check
if "%INPUT%"=="" (
    echo usage: khtk app.htk [-o app.exe] [--run] >&2
    exit /b 1
)

if "%OUTPUT%"=="" (
    set OUTPUT=%~n1.exe
    for %%F in ("%INPUT%") do set OUTPUT=%%~nF.exe
)

echo khtk: compiling %INPUT% ... >&2
kcc "%INPUT%" > "%TMP%"
if errorlevel 1 ( echo khtk: compile failed >&2 & del /Q "%TMP%" 2>nul & exit /b 1 )

echo khtk: linking %OUTPUT% ... >&2
gcc "%TMP%" -o "%OUTPUT%" -lws2_32 -w
if errorlevel 1 ( echo khtk: link failed >&2 & del /Q "%TMP%" 2>nul & exit /b 1 )

del /Q "%TMP%" 2>nul
echo khtk: built %OUTPUT% >&2

if "%RUN%"=="1" (
    echo khtk: running %OUTPUT% ... >&2
    "%OUTPUT%"
)
endlocal
