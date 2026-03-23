@echo off
setlocal
echo ============================================================
echo  Krypton v0.9.7 Build Script
echo ============================================================

set KCC=versions\kcc_v095.exe
set COMPILE=kompiler\compile.k
set OUT_C=compile_out.c
set OUT_EXE=versions\kcc_v097.exe

echo.
echo [1/5] Verifying on features_test.k...
%KCC% examples\features_test.k > test_features.c
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
gcc test_features.c -o test_features.exe -w
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
test_features.exe
echo OK

echo.
echo [2/5] Compiling resource...
windres assets\krypton.rc -O coff -o krypton.res
if errorlevel 1 ( set RES= ) else ( set RES=krypton.res & echo OK )

echo.
echo [3/5] Self-hosting with kcc_v095...
%KCC% %COMPILE% %COMPILE% > %OUT_C%
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
echo OK

echo.
echo [4/5] Compiling to %OUT_EXE%...
gcc %OUT_C% %RES% -o %OUT_EXE% -lm -w
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
echo OK

echo.
echo ============================================================
echo  SUCCESS: %OUT_EXE% built!
echo ============================================================

echo.
echo [5/5] Running v0.9.7 tests...
%OUT_EXE% test_v097.k > test_v097_out.c
if errorlevel 1 ( echo FAILED: compile & pause & exit /b 1 )
gcc test_v097_out.c -o test_v097.exe -lm -w
if errorlevel 1 ( echo FAILED: gcc & pause & exit /b 1 )
test_v097.exe
if errorlevel 1 ( echo FAILED: run & pause & exit /b 1 )

echo.
echo Done! kcc_v097.exe built and tested.
pause
endlocal
