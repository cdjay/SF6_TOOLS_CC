@echo off
setlocal
cd /d "%~dp0\..\.."
set "VERSION_ARG="
if not "%~1"=="" set "VERSION_ARG=--version %~1"

where py >nul 2>nul
if %errorlevel%==0 (
  py -3 tools\modern_display_builder\official_snapshot_tool.py %VERSION_ARG%
) else (
  python tools\modern_display_builder\official_snapshot_tool.py %VERSION_ARG%
)
set "EXIT_CODE=%errorlevel%"
echo.
if not "%EXIT_CODE%"=="0" echo Official data fetch/diff failed. Exit code: %EXIT_CODE%
if "%EXIT_CODE%"=="0" echo Official data fetch/diff completed.
pause
exit /b %EXIT_CODE%
