@echo off
REM bootstrap.bat - install Krypton from prebuilt binaries (no gcc required)
REM
REM Run this once after `git clone` on Windows. Copies the bootstrap binaries
REM into place so kcc and the kr launcher work without any C compiler.
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
if not exist compiler\windows_x86 mkdir compiler\windows_x86
copy /Y "%SEED_X64%" compiler\windows_x86\x64_host.exe >nul      && echo   OK  compiler\windows_x86\x64_host.exe
copy /Y "%SEED_OPT%" compiler\windows_x86\optimize_host.exe >nul && echo   OK  compiler\windows_x86\optimize_host.exe
copy /Y runtime\krypton_rt.dll krypton_rt.dll >nul      && echo   OK  krypton_rt.dll
echo.

REM Smoke test
kcc.exe --version 2>nul
echo.
echo Bootstrap complete. Try:
echo   kcc examples\hello.k -o hello.exe   (compile to native PE)
echo   hello.exe                           (run the native binary)
echo   kcc -e "kp(\"hi\")"                 (one-shot eval)
echo   kr script.ks                        (auto-wrap top-level script)
echo.
echo Notes:
echo   - kcc is the Krypton-native driver (kcc.ks compiled). No bash needed.
echo   - In Git Bash / MSYS2, prefer forward slashes for paths
echo     (examples/hello.k). Bash treats \h as an escape.
echo   - Do NOT run kcc under WSL bash on Windows: WSL bash produces a
echo     Linux ELF instead of a Windows PE/COFF, and Windows will reject
echo     the result.

endlocal
