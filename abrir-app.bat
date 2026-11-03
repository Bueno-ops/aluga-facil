@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo  Aluga Facil - servidor local
echo  Abra http://localhost:8099/app.html no navegador
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "servidor-local.ps1"
echo.
echo Servidor encerrado.
pause
