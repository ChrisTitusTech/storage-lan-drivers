echo Please wait while installing drivers. Do not turn off or unplug the computer power during the installation...
@echo off

cd %~dp0

%windir%/system32/pnputil /add-driver "%~dp0aqnic650.inf" /install

ping 127.0.0.1 -n 5 -w 1000 > nul

EXIT 


