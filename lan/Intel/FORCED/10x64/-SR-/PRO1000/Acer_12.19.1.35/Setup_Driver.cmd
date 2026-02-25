@echo off
REM Create by MVP v2.0.8.2
title Installing INTEL LAN Generic Driver
if not exist C:\OEM\AcerLogs md C:\OEM\AcerLogs
SET LogPath=C:\OEM\AcerLogs\DriverInstallation.log

:: BatchGotAdmin
:-------------------------------------
REM  --> Check for permissions
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

REM --> If error flag set, we do not have admin.
IF '%errorlevel%' NEQ '0' (
    ECHO Requesting administrative privileges...
    GOTO UACPrompt
) ELSE GOTO gotAdmin

:UACPrompt
ECHO Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
ECHO UAC.ShellExecute "%~s0", "%~s1", "", "runas", 1 >> "%temp%\getadmin.vbs"

"%temp%\getadmin.vbs"
del /q "%temp%\getadmin.vbs"
EXIT /B 1

:gotAdmin
ECHO.>>%LogPath%
ECHO Installing, please wait...
pushd "%~dp0"

ECHO %DATE% %TIME%[Log START]  ============ %~dpnx0 ============ >> %LogPath%

if exist C:\OEM\Preload\Command\POP*.ini ECHO [INTEL LAN Generic Driver]>> C:\OEM\Preload\OEMINFLIST.ini
for /f "tokens=*" %%v in (InfFiles.txt) do (
    ECHO %DATE% %TIME%[Log TRACE]  pnputil /add-driver "%%v" /install >> %LogPath%
    pnputil /add-driver "%%v" /install >> %LogPath% 2>&1
    ECHO %DATE% %TIME%[Log TRACE]  pnputil -i -a "%%v" >> %LogPath%
    pnputil -i -a "%%v" >> %LogPath% 2>&1
    ECHO.>>%LogPath%

    for /f "skip=1 tokens=2 delims=,;" %%s in ('find /i "DriverVer" "%%v"') do (
        if exist C:\OEM\Preload\Command\POP*.ini ECHO %%~nxv=%%s>> C:\OEM\Preload\OEMINFLIST.ini
    )
)
if exist C:\OEM\Preload\Command\POP*.ini ECHO.>> C:\OEM\Preload\OEMINFLIST.ini

timeout /t 5 >NUL 2>&1
ECHO Installation process completed.
ECHO Press any key to exit
PAUSE >NUL

ECHO %DATE% %TIME%[Log Leave]  ============ %~dpnx0 ============ >> %LogPath%
ECHO.>>%LogPath%

popd
