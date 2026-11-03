@echo off
rem Build the TFG project on Windows without PowerShell ExecutionPolicy restrictions.
rem Usage:
rem   build.bat          (compile the project)
rem   build.bat -Clean   (clean auxiliary files)

setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %ERRORLEVEL%
