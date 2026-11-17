@echo off
echo [1/2] Building Windows SMS Client...
call flutter build windows --release --target lib/main_client.dart

echo [2/2] Done!
echo Executable is located in: build\windows\x64\runner\Release\android_host.exe
pause
