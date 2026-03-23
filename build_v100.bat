@echo off
setlocal
echo ============================================================
echo  Krypton v1.0.0 Build Script
echo ============================================================

set KCC=versions\kcc_v098.exe
set COMPILE=kompiler\compile.k
set OUT_C=compile_out.c
set OUT_EXE=versions\kcc_v100.exe

echo.
echo [1/5] Verifying on features_test.k...
%KCC% examples\features_test.k > test_features.c
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
gcc test_features.c -o test_features.exe -lm -w
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
test_features.exe
echo OK

echo.
echo [2/5] Compiling resource...
windres assets\krypton.rc -O coff -o krypton.res
if errorlevel 1 ( set RES= ) else ( set RES=krypton.res & echo OK )

echo.
echo [3/5] Self-hosting with kcc_v098...
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
echo [5/5] Running v1.0.0 comprehensive tests...
%OUT_EXE% test_v100.k > test_v100_out.c
if errorlevel 1 ( echo FAILED: compile & pause & exit /b 1 )
gcc test_v100_out.c -o test_v100.exe -lm -w
if errorlevel 1 ( echo FAILED: gcc & pause & exit /b 1 )
test_v100.exe
if errorlevel 1 ( echo FAILED: run & pause & exit /b 1 )

echo.
echo Done! kcc_v100.exe built and tested.
pause
endlocal
