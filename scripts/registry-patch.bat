@echo off
:: registry-patch.bat
:: Elevates and runs registry-patch.ps1 as Administrator.
:: Double-click this file inside the Windows VM to apply all patches.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo [*] Running registry artifact scrubber...
powershell -ExecutionPolicy Bypass -File "%~dp0registry-patch.ps1"

echo.
echo [+] Registry patching complete.
echo [!] Please reboot the VM now.
pause
