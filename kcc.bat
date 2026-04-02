@echo off
setlocal enabledelayedexpansion

REM kcc.bat - Krypton compiler driver
REM Usage: kcc source.k [-o output.exe] [-lFOO ...] [--ir]
REM
REM Without -o: writes C to stdout (same as kcc.exe)
REM With -o:    compiles all the way to a native .exe via gcc

set KCC_EXE=%~dp0kcc.exe
set SRCFILE=
set OUTFILE=
set LIBS=-lm -w
set PASSTHROUGH=
set IRMODE=

:parse
if "%~1"=="" goto endparse
if /I "%~1"=="--ir" (
    set IRMODE=--ir
    shift & goto parse
)
if /I "%~1"=="-o" (
    set OUTFILE=%~2
    shift & shift & goto parse
)
if "%~1:~0,2%"=="-l" ( set LIBS=!LIBS! %~1 & shift & goto parse )
if "%~1:~0,2%"=="-L" ( set LIBS=!LIBS! %~1 & shift & goto parse )
if "%~1:~0,2%"=="-W" ( set LIBS=!LIBS! %~1 & shift & goto parse )
set SRCFILE=%~1
shift
goto parse

:endparse

if "%SRCFILE%"=="" (
    echo kcc: no input file 1>&2
    exit /b 1
)

if "%OUTFILE%"=="" (
    REM No -o: pipe C to stdout as usual
    "%KCC_EXE%" %IRMODE% "%SRCFILE%"
    exit /b %ERRORLEVEL%
)

REM -o mode: compile to native exe
set TMPFILE=%OUTFILE%__kcc_tmp.c
"%KCC_EXE%" %IRMODE% "%SRCFILE%" > "%TMPFILE%"
if errorlevel 1 (
    del /F /Q "%TMPFILE%" 2>nul
    echo kcc: Krypton compilation failed 1>&2
    exit /b 1
)
gcc "%TMPFILE%" -o "%OUTFILE%" %LIBS%
set GCCRET=%ERRORLEVEL%
del /F /Q "%TMPFILE%" 2>nul
if %GCCRET% neq 0 (
    echo kcc: C compilation failed 1>&2
    exit /b 1
)
exit /b 0
