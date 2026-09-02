@echo off
rem Terminal Board shim - installed by Terminal Board.
call "%~dp0TerminalBoard\tb.cmd" %*
exit /b %ERRORLEVEL%
