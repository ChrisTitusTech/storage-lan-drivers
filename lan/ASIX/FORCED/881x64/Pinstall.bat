@echo off
If "%PROCESSOR_ARCHITECTURE%" EQU "x86" (
    If exist "%SystemRoot%\SysWOW64" (
        "%SystemRoot%\sysnative\cmd.exe" /C "%~dpnx0" %1 %2 %3 %4 %5 %6 %7 %8 %9
        exit
    )
)
cd /d %~dp0
echo ----- start: %date% %time% >> log.txt
echo %~dp0 >> log.txt
setlocal

if /i "%1"  == "-FirstLogon" (
    if "%2" == "0000" call :FirstLogon_0000
) else if "%1"=="" (
    call :FirstLogon_0000
) else goto END

:END
endlocal
echo ----- end: %date% %time% >> log.txt
goto :eof

:FirstLogon_0000
>> log.txt echo cmd: pnputil.exe /add-driver netmosu.inf /install
start /b /wait pnputil.exe /add-driver netmosu.inf /install
if errorlevel 1 echo "%date% ERRORLEVEL:%ERRORLEVEL%" >> log.txt
exit /b


