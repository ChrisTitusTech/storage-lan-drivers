@REM ==================================================================
@REM Installation of the full Allied Telesis driver package.
@REM Copyright 2019 HP Inc.
@REM ==================================================================

@echo off
@REM set TMP=C:\

echo Installing Allied Telesis Fiber NIC Driver...

echo It is recommended to restart the computer when the installation is completed.

echo Please wait...

pnputil.exe /a atind60a.inf /i

echo ==================================================================

echo Installation completed. Please restart the computer...

timeout /t 10