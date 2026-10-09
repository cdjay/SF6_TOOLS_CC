@echo off
setlocal
cd /d "%~dp0\..\.."
if "%~1"=="" (
  echo Usage: 3_deploy_command_display.bat ^<version^> [--check] [--characters Arjun]
  pause
  exit /b 2
)
rem Copies acbcm\<version>\lastjson into data\TrainingComboTrials_data\command_display.
rem --check only compares and changes nothing.
node tools\action_runtime_compiler\deploy_command_display.js --version %~1 %2 %3 %4
set "EXIT_CODE=%errorlevel%"
echo.
if not "%EXIT_CODE%"=="0" echo command_display deploy/check failed. Exit code: %EXIT_CODE%
if "%EXIT_CODE%"=="0" echo command_display deploy/check completed.
pause
exit /b %EXIT_CODE%
