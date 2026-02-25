$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path
cd $scriptRoot
pnputil.exe /add-driver .\*.inf /subdirs /install