@echo off
setlocal
cd /d "%~dp0\..\.."
set "VERSION_ARG="
if not "%~1"=="" set "VERSION_ARG=--version %~1"
rem Extra options after the version, e.g. --allow-missing-official or --characters Arjun.
set "EXTRA_ARGS=%2 %3 %4 %5"

node tools\action_runtime_compiler\lastjson_builder.js %VERSION_ARG% %EXTRA_ARGS%
set "EXIT_CODE=%errorlevel%"
echo.
if not "%EXIT_CODE%"=="0" echo lastjson build failed. Exit code: %EXIT_CODE%
if "%EXIT_CODE%"=="0" echo lastjson build completed.
pause
exit /b %EXIT_CODE%
