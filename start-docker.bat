@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-EazyHermes-Docker.ps1" %*
if errorlevel 1 (
  echo.
  echo EazyHermes Docker start failed. Press any key to close this window.
  pause >nul
)

