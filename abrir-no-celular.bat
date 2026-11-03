@echo off
chcp 65001 >nul
title Aluga Facil - abrir no celular
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0abrir-no-celular.ps1"
echo.
echo Pressione qualquer tecla para fechar esta janela.
pause >nul
