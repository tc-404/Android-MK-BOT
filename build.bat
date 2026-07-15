@echo off
chcp 65001 >nul
title Android DIY Sandbox - 构建 APK
echo.
echo  ========================================
echo   Android DIY Sandbox 一键构建 APK
echo  ========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-apk.ps1" -BuildType debug
if errorlevel 1 (
    echo.
    echo  构建失败。如果提示找不到 Flutter，请先运行 setup.bat
    pause
    exit /b 1
)

echo.
pause
