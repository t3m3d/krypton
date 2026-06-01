@echo off
REM build.bat - compile kls.exe (Krypton Language Server)
REM Run from repo root: lsp\build.bat

set ROOT=%~dp0..
pushd %ROOT%

echo [1/2] kcc.exe lsp\kls.k -^> lsp\_kls.c
.\kcc.exe lsp\kls.k > lsp\_kls.c
if errorlevel 1 ( echo kcc failed & popd & exit /b 1 )

echo [2/2] gcc lsp\_kls.c -^> kls.exe
gcc lsp\_kls.c -o kls.exe -w
if errorlevel 1 ( echo gcc failed & popd & exit /b 1 )

echo.
echo built kls.exe
dir /B kls.exe
popd
