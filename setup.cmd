@echo off
setlocal
title Install Terminal Board
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 (
  echo.
  echo Installation failed. See the errors above.
  pause
  exit /b 1
)
echo.
echo Installation complete.
echo   - Terminal Board icon on the Desktop: choose the panes and agents, then open the workspace
echo   - Take a screenshot (Win+Shift+S), then Ctrl+V in the terminal to send it to an agent
echo.
echo Press any key to open Terminal Board now...
pause >nul
start "" "%LOCALAPPDATA%\Microsoft\WindowsApps\TerminalBoard\TbClipboardHelper.exe" --desk
