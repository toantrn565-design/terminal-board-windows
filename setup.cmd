@echo off
setlocal
title Install Terminal Board
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 (
  echo.
  echo Cai dat that bai. Xem loi o tren.
  pause
  exit /b 1
)
echo.
echo Cai dat thanh cong. Go: tb 5
pause
