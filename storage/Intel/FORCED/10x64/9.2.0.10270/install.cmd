@echo off
echo.
echo Starting Intel(R) VROC Driver Installation...
echo.

pnputil /add-driver "%~dp0\*.inf" /install > nul

if errorlevel 3010 goto reboot
if errorlevel 259 goto nothing
if errorlevel 5 goto elevated
if errorlevel 1 goto error

:success
echo Intel(R) VROC drivers installed. Please reboot the system.
goto end

:reboot
echo Intel(R) VROC drivers installed. Please reboot the system.
goto end

:nothing
echo Intel(R) VROC drivers already installed.
goto end

:elevated
echo Intel(R) VROC Driver Installation failed. Please run this installer from an elevated command prompt.
goto end

:error
echo Errorlevel: %errorlevel%
echo Please check driver installation in Windows Device Manager.

:end
echo.
pause
