@echo off
setlocal

set "REPO_ROOT=%~dp0.."
set "OUTPUT=%REPO_ROOT%\audit-output\semantic-governance-dashboard.html"

where node >nul 2>nul
if errorlevel 1 (
    echo Node.js is required to analyze the SF6CC repository.
    exit /b 1
)

node "%~dp0semantic_governance_dashboard.mjs" ^
    --repo-root "%REPO_ROOT%" ^
    --output "%OUTPUT%" ^
    --open

if errorlevel 1 exit /b 1
endlocal
