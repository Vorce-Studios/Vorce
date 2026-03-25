@echo off
setlocal
call "%~dp0vorce\\run-vorce.bat" %*
exit /b %ERRORLEVEL%
