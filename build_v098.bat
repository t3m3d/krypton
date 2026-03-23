@echo off
setlocal
echo ============================================================
echo  Krypton v0.9.8 Build Script
echo ============================================================

set KCC=versions\kcc_v097.exe
set COMPILE=kompiler\compile.k
set OUT_C=compile_out.c
set OUT_EXE=versions\kcc_v098.exe

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
echo [3/5] Self-hosting with kcc_v097...
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
echo [5/5] Running v0.9.8 C-mode tests...
%OUT_EXE% test_v098.k > test_v098_out.c
if errorlevel 1 ( echo FAILED: compile & pause & exit /b 1 )
gcc test_v098_out.c -o test_v098.exe -lm -w
if errorlevel 1 ( echo FAILED: gcc & pause & exit /b 1 )
test_v098.exe
if errorlevel 1 ( echo FAILED: run & pause & exit /b 1 )

echo.
echo [6/6] Testing LLVM pipeline on test_ir.k...
%OUT_EXE% --ir test_ir.k > test_ir.kir
if errorlevel 1 ( echo FAILED: IR gen & pause & exit /b 1 )
%OUT_EXE% kompiler\optimize.k test_ir.kir > test_ir_opt.kir
if errorlevel 1 ( echo FAILED: optimizer & pause & exit /b 1 )
%OUT_EXE% kompiler\llvm.k test_ir_opt.kir > test_ir.ll
if errorlevel 1 ( echo FAILED: LLVM gen & pause & exit /b 1 )
echo.
echo LLVM IR generated: test_ir.ll
echo Contents:
type test_ir.ll
echo.
echo Done! Full pipeline: .k -> .kir -> .kir (opt) -> .ll
echo To compile to native: clang test_ir.ll runtime\krypton_runtime.c -o test_ir_native.exe -lm

echo.
echo Done! kcc_v098.exe built and tested.
pause
endlocal
