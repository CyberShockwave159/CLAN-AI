@echo off
REM Build CLAN-AI Windows installer (.exe)
REM Requires: Flutter SDK, NSIS (makensis in PATH)
REM Run this from the project root directory

echo ============================================
echo   CLAN-AI Windows Installer Builder
echo ============================================
echo.

REM Step 1: Verify Flutter setup
echo [1/6] Verifying Flutter setup...
where flutter >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Flutter is not installed or not in PATH
    echo Download from: https://flutter.dev/docs/get-started/install/windows
    pause
    exit /b 1
)
call flutter --version
call flutter pub get
echo.

REM Step 2: Build Windows release binary
echo [2/6] Building Windows release binary...
call flutter build windows --release
echo.

REM Step 3: Build MSIX package
echo [3/6] Building MSIX package...
call dart run msix:create
echo.

REM Step 4: Find the generated MSIX file
echo [4/6] Locating MSIX package...
set "MSIX_FILE="
for %%f in (build\msix\windows\*.msix) do set "MSIX_FILE=%%f"
if "%MSIX_FILE%"=="" (
    for %%f in (build\msix\*.msix) do set "MSIX_FILE=%%f"
)
if "%MSIX_FILE%"=="" (
    echo ERROR: MSIX file not found after build
    echo Expected at: build\msix\windows\*.msix
    pause
    exit /b 1
)
echo     Found MSIX: %MSIX_FILE%
echo.

REM Step 5: Prepare distribution directory
echo [5/6] Preparing distribution directory...
if not exist "dist" mkdir dist
copy /y "%MSIX_FILE%" "dist\clan_ai_%date:~-4%%date:~-7,2%%date:~-4,2%.msix" >nul 2>&1 || copy /y "%MSIX_FILE%" "dist\clan_ai_%.msix"
echo     Copied to dist\ directory
echo.

REM Step 6: Build NSIS installer (optional - requires makensis)
echo [6/6] Building NSIS installer...
where makensis >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo     NSIS found, building installer...
    makensis /DMSIX_SOURCE="%MSIX_FILE%" /DDIST_DIR="dist" installer\nsis_installer.nsi
    echo     NSIS installer built successfully
) else (
    echo     WARNING: NSIS (makensis) not found in PATH
    echo     Skipping NSIS installer step.
    echo     The MSIX file can be installed manually by double-clicking it.
)
echo.

echo ============================================
echo   Build Complete!
echo ============================================
echo.
echo Distribution files are in: dist\
echo.
dir dist\
echo.
echo Next steps:
echo   1. Upload files to GitHub Releases
echo   2. Share the .exe installer with users
echo.
pause
