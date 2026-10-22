@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0add_to_path.ps1" %*
pause
