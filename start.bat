@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-eazyhermes.ps1" %*
if errorlevel 1 (
  echo.
  echo EazyHermes failed to start. Press any key to close this window.
  pause >nul
)

