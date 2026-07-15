@echo off
chcp 65001 >nul
title Android DIY Sandbox - 一键安装

echo.
echo  ========================================
echo   Android DIY Sandbox  一键环境安装
echo  ========================================
echo.
echo  将自动安装到 C:\dev\ 目录:
echo    - JDK 17
echo    - Flutter SDK
echo    - Android SDK + NDK
echo    - 项目副本 (避免中文路径导致编译失败)
echo.
echo  首次运行约需 20-40 分钟, 请保持网络畅通。
echo.
echo  按任意键开始...
pause >nul

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-windows.ps1" %*

echo.
pause
