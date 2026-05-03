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
copy /Y "%SEED_X64%" compiler\x64_host.exe >nul      && echo   OK  compiler\x64_host.exe
copy /Y "%SEED_OPT%" compiler\optimize_host.exe >nul && echo   OK  compiler\optimize_host.exe
echo   OK  runtime\krypton_rt.dll (already present)
echo.

REM Smoke test
kcc.exe --version 2>nul
echo.
echo Bootstrap complete. Try:
echo   kcc.exe examples\hello.k                              (emit C source to stdout)
echo   bash kcc.sh --native examples/hello.k -o hello.exe    (native PE — use forward slashes in bash!)
echo   hello.exe                                              (run the native binary)
echo.
echo Notes:
echo   - In bash, use forward slashes (examples/hello.k). Bash treats \h as escape.
echo   - Run kcc.sh from cmd/PowerShell-launched bash (git-bash, MSYS2). Do NOT
echo     run it from WSL bash on Windows: WSL bash will produce a Linux ELF
echo     instead of a Windows PE/COFF, and Windows will reject the result.

endlocal
