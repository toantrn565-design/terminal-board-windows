@echo off
rem Terminal Board shim - installed by Terminal Board.
call "%LOCALAPPDATA%\TerminalBoard\bin\tb.cmd" %*
exit /b %ERRORLEVEL%
