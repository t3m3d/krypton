@echo off
REM bootstrap.bat - install Krypton from prebuilt binaries (no gcc required)
REM
REM Run this once after `git clone` on Windows. Copies the bootstrap binaries
REM into place so kcc, kcc.sh --native, etc. work without any C compiler.
REM
REM For a from-source rebuild (with icon, version bump, etc.), use build_v137.bat.

setlocal

set BOOT=bootstrap
set OS=windows
set ARCH=x86_64

set SEED_KCC=%BOOT%\kcc_seed_%OS%_%ARCH%.exe
set SEED_X64=%BOOT%\x64_host_%OS%_%ARCH%.exe
set SEED_OPT=%BOOT%\optimize_host_%OS%_%ARCH%.exe

if not exist "%SEED_KCC%" ( echo FAIL: missing %SEED_KCC% & exit /b 1 )
if not exist "%SEED_X64%" ( echo FAIL: missing %SEED_X64% & exit /b 1 )
if not exist "%SEED_OPT%" ( echo FAIL: missing %SEED_OPT% & exit /b 1 )
if not exist runtime\krypton_rt.dll ( echo FAIL: missing runtime\krypton_rt.dll & exit /b 1 )

echo Installing prebuilt Krypton binaries (no gcc needed)...
echo.
copy /Y "%SEED_KCC%" kcc.exe >nul                    && echo   OK  kcc.exe
copy /Y "%SEED_X64%" kompiler\x64_host.exe >nul      && echo   OK  kompiler\x64_host.exe
copy /Y "%SEED_OPT%" kompiler\optimize_host.exe >nul && echo   OK  kompiler\optimize_host.exe
echo   OK  runtime\krypton_rt.dll (already present)
echo.

REM Smoke test
kcc.exe --version 2>nul
echo.
echo Bootstrap complete. Try:
echo   kcc.exe examples\hello.k                         (emit C to stdout)
echo   bash kcc.sh --native examples\hello.k -o hello.exe   (native PE, no gcc)

endlocal
