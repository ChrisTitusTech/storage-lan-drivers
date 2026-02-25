@echo off
echo.
echo Starting driver installation...
echo.

cd /D "%~dp0"
Powershell.exe -ExecutionPolicy Bypass -Command "& '.\Install.ps1'"

echo.
echo Driver installation complete.
echo.