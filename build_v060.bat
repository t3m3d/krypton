@echo off
setlocal
echo ============================================================
echo  Krypton v0.6.0 Build Script
echo ============================================================

set KCC=versions\kcc_v050.exe
set COMPILE=kompiler\compile.k
set OUT_C=compile_out.c
set OUT_EXE=versions\kcc_v060.exe

:: Step 1 - Compile a test program to verify the compiler works
echo.
echo [1/4] Verifying compiler on features_test.k...
%KCC% %COMPILE% examples\features_test.k > test_features.c
if errorlevel 1 (
    echo FAILED: compiler crashed on features_test.k
    exit /b 1
)
echo OK - generated test_features.c

:: Step 2 - Build and run the features test
echo.
echo [2/4] Building and running features test...
gcc test_features.c -o test_features.exe -w 2>nul
if errorlevel 1 (
    cl test_features.c /Fe:test_features.exe /w 2>nul
    if errorlevel 1 (
        echo FAILED: could not compile test_features.c
        exit /b 1
    )
)
test_features.exe
echo.

:: Step 3 - Self-host: compile compile.k with itself
echo [3/4] Self-hosting: compiling compile.k with kcc_v050...
%KCC% %COMPILE% %COMPILE% > %OUT_C%
if errorlevel 1 (
    echo FAILED: self-host compilation crashed
    exit /b 1
)
echo OK - generated %OUT_C%

:: Step 4 - Compile the C output to produce kcc_v060.exe
echo.
echo [4/4] Compiling %OUT_C% to %OUT_EXE%...
gcc %OUT_C% -o %OUT_EXE% -w 2>nul
if errorlevel 1 (
    cl %OUT_C% /Fe:%OUT_EXE% /w /link krypton.res 2>nul
    if errorlevel 1 (
        cl %OUT_C% /Fe:%OUT_EXE% /w 2>nul
        if errorlevel 1 (
            echo FAILED: could not compile %OUT_C%
            exit /b 1
        )
    )
)

echo.
echo ============================================================
echo  SUCCESS: %OUT_EXE% built!
echo ============================================================
echo.

:: Step 5 - Verify v060 can run the test
echo [5/5] Verifying kcc_v060 on test_v060.k...
%OUT_EXE% %COMPILE% test_v060.k > test_v060_out.c
if errorlevel 1 (
    echo WARNING: kcc_v060 could not compile test_v060.k
    exit /b 1
)
gcc test_v060_out.c -o test_v060.exe -w 2>nul
if errorlevel 1 (
    cl test_v060_out.c /Fe:test_v060.exe /w
)
test_v060.exe

endlocal
