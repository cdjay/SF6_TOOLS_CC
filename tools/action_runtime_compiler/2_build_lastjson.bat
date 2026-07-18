@echo off
setlocal
cd /d "%~dp0\..\.."
set "VERSION_ARG="
if not "%~1"=="" set "VERSION_ARG=--version %~1"

node tools\action_runtime_compiler\lastjson_builder.js %VERSION_ARG%
set "EXIT_CODE=%errorlevel%"
echo.
if not "%EXIT_CODE%"=="0" echo lastjson build failed. Exit code: %EXIT_CODE%
if "%EXIT_CODE%"=="0" echo lastjson build completed.
pause
exit /b %EXIT_CODE%
