@echo off
echo [1/4] Building Web Client...
call flutter build web --release --target lib/main_web.dart --base-href / --no-tree-shake-icons

echo [2/4] Cleaning old assets...
if exist assets\web.zip del assets\web.zip
if not exist assets mkdir assets

echo [3/4] Zipping Web Client...
:: Используем PowerShell для создания zip (встроено в Windows)
powershell -command "Compress-Archive -Path 'build\web\*' -DestinationPath 'assets\web.zip' -Force"

echo [4/4] Running Android Host...
call flutter run