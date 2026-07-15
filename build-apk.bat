@echo off
chcp 65001 >nul
title Android DIY Sandbox - 构建 APK

echo.
echo  构建 Debug APK (工作目录: C:\dev\Android-DIY-Sandbox-master)
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-apk.ps1" %*

echo.
pause
