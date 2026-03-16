@echo off
setlocal
call "%~dp0subi\\run-subi.bat" %*
exit /b %ERRORLEVEL%
