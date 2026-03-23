@echo off
setlocal
echo ============================================================
echo  Krypton LLVM Pipeline
echo ============================================================
echo Usage: build_llvm.bat source.k

set SRC=%1
if "%SRC%"=="" ( echo Error: no source file & pause & exit /b 1 )
set BASE=%~n1
set KCC=versions\kcc_v098.exe
set CLANG="C:\Program Files\LLVM\bin\clang.exe"
set RUNTIME=runtime\krypton_runtime.c

echo.
echo [1/6] Building optimizer...
%KCC% kompiler\optimize.k > _opt_build.c
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
gcc _opt_build.c -o _optimizer.exe -w
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
echo OK

echo.
echo [2/6] Building LLVM backend...
%KCC% kompiler\llvm.k > _llvm_build.c
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
gcc _llvm_build.c -o _llvmbe.exe -w
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
echo OK

echo.
echo [3/6] Compiling %SRC% to IR...
%KCC% --ir %SRC% > %BASE%.kir
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
echo OK - %BASE%.kir

echo.
echo [4/6] Optimizing IR...
_optimizer.exe %BASE%.kir > %BASE%_opt.kir
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
echo OK - %BASE%_opt.kir

echo.
echo [5/6] Generating LLVM IR...
_llvmbe.exe %BASE%_opt.kir > %BASE%.ll
if errorlevel 1 ( echo FAILED & pause & exit /b 1 )
echo OK - %BASE%.ll

echo.
echo [6/6] Compiling to native...
gcc -c %RUNTIME% -o krypton_runtime.o -w
if errorlevel 1 ( echo FAILED: runtime & pause & exit /b 1 )
%CLANG% -c %BASE%.ll -o %BASE%_ll.o --target=x86_64-w64-mingw32 -Wno-override-module
if errorlevel 1 ( echo FAILED: clang compile & pause & exit /b 1 )
gcc %BASE%_ll.o krypton_runtime.o -o %BASE%_llvm.exe -w
if errorlevel 1 ( echo FAILED: link & pause & exit /b 1 )
echo OK - %BASE%_llvm.exe

echo.
echo ============================================================
echo  Running %BASE%_llvm.exe
echo ============================================================
%BASE%_llvm.exe

echo.
echo Done!
pause
endlocal
