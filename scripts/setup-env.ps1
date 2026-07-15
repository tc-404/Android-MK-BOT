# Android DIY Sandbox - one-click env setup (Windows)
param(
    [switch]$SkipBuild,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$DevRoot     = Join-Path $env:LOCALAPPDATA "diy-sandbox-dev"
$FlutterDir  = Join-Path $DevRoot "flutter"
$AndroidSdk  = Join-Path $DevRoot "android-sdk"
$JdkDir      = Join-Path $DevRoot "jdk-17"
$JniLibsDir  = Join-Path $ProjectRoot "android\app\src\main\jniLibs\arm64-v8a"

$SdkPackages = @(
    "platform-tools",
    "platforms;android-35",
    "build-tools;35.0.0",
    "ndk;27.0.12077973",
    "cmake;3.22.1"
)

function Write-Step([string]$Msg) { Write-Host ""; Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Skip([string]$Msg) { Write-Host "  [SKIP] $Msg" -ForegroundColor Yellow }
function Write-Fail([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    # winget 刚装的 Git 可能还没写入当前会话 PATH
    $gitPaths = @(
        "C:\Program Files\Git\cmd",
        "C:\Program Files\Git\bin"
    )
    foreach ($p in $gitPaths) {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
            $env:Path = "$env:Path;$p"
        }
    }
}

# 脚本启动时立即刷新 PATH
Refresh-Path

function Set-UserEnv([string]$Name, [string]$Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "env:$Name" -Value $Value
}

function Add-UserPath([string]$Dir) {
    if (-not (Test-Path $Dir)) { return }
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($current -notlike "*$Dir*") {
        [Environment]::SetEnvironmentVariable("Path", "$current;$Dir", "User")
        $env:Path = "$env:Path;$Dir"
    }
}

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-WingetInstall([string]$Id, [string]$Label) {
    $listed = winget list --id $Id --disable-interactivity 2>&1
    if ($LASTEXITCODE -eq 0 -and ($listed -match [regex]::Escape($Id))) {
        Write-Skip "$Label already installed"
        return
    }
    Write-Host "  Installing $Label ..."
    Write-Host "  (If UAC prompt appears, click YES / Shi)" -ForegroundColor Yellow
    winget install --id $Id --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw "winget install failed for $Label (exit $LASTEXITCODE)" }
    Write-Ok "$Label installed"
    Refresh-Path
}

function Find-JavaHome {
    if (Test-Path (Join-Path $JdkDir "bin\java.exe")) { return $JdkDir }
    $dirs = @(
        "C:\Program Files\Eclipse Adoptium",
        "C:\Program Files\Microsoft",
        "C:\Program Files\Java"
    )
    foreach ($base in $dirs) {
        $hit = Get-ChildItem "$base\jdk-17*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Install-JdkZip {
    if ((Test-Path (Join-Path $JdkDir "bin\java.exe")) -and -not $Force) {
        Write-Skip "JDK 17 exists: $JdkDir"
        return
    }
    New-Item -ItemType Directory -Force -Path $DevRoot | Out-Null
    Write-Host "  Downloading JDK 17 zip (no admin required)..."
    $zipPath = Join-Path $env:TEMP "jdk17.zip"
    $urls = @(
        "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.19+10/OpenJDK17U-jdk_x64_windows_hotspot_17.0.19_10.zip",
        "https://mirrors.huaweicloud.com/java/jdk/17.0.2+8/OpenJDK17U-jdk_x64_windows_hotspot_17.0.2_8.zip"
    )
    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
            $downloaded = $true; break
        } catch {
            Write-Host "  Download failed: $url" -ForegroundColor Yellow
        }
    }
    if (-not $downloaded) { throw "JDK 17 zip download failed" }

    $extractDir = Join-Path $env:TEMP "jdk17-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    Remove-Item $zipPath -Force

    $inner = Get-ChildItem $extractDir -Directory | Select-Object -First 1
    if (-not $inner) { throw "JDK zip extract failed" }
    if (Test-Path $JdkDir) { Remove-Item $JdkDir -Recurse -Force }
    Move-Item $inner.FullName $JdkDir
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "JDK 17 ready: $JdkDir"
}

function Install-Flutter {
    if ((Test-Path (Join-Path $FlutterDir "bin\flutter.bat")) -and -not $Force) {
        Write-Skip "Flutter exists: $FlutterDir"
        return
    }
    New-Item -ItemType Directory -Force -Path $DevRoot | Out-Null
    if (-not (Test-Command git)) { throw "Git not found. Re-run setup or install Git manually." }

    if (Test-Path $FlutterDir) { Remove-Item $FlutterDir -Recurse -Force }
    Write-Host "  Cloning Flutter SDK (stable, ~1GB)..."
    $mirrors = @(
        "https://gitee.com/mirrors/Flutter.git",
        "https://github.com/flutter/flutter.git"
    )
    $cloned = $false
    foreach ($url in $mirrors) {
        git clone --depth 1 -b stable $url $FlutterDir 2>&1 | Out-Host
        if (Test-Path (Join-Path $FlutterDir "bin\flutter.bat")) { $cloned = $true; break }
        if (Test-Path $FlutterDir) { Remove-Item $FlutterDir -Recurse -Force }
        Write-Host "  Mirror failed: $url" -ForegroundColor Yellow
    }
    if (-not $cloned) { throw "Flutter clone failed on all mirrors" }
    Write-Ok "Flutter ready: $FlutterDir"
}

function Install-AndroidSdk {
    $sdkmanager = Join-Path $AndroidSdk "cmdline-tools\latest\bin\sdkmanager.bat"
    if ((Test-Path $sdkmanager) -and -not $Force) {
        Write-Skip "Android SDK exists: $AndroidSdk"
        return
    }
    New-Item -ItemType Directory -Force -Path $AndroidSdk | Out-Null
    Write-Host "  Downloading Android command-line tools..."
    $zipPath = Join-Path $env:TEMP "cmdline-tools.zip"
    $urls = @(
        "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip",
        "https://mirrors.cloud.tencent.com/AndroidSDK/commandlinetools-win-11076708_latest.zip"
    )
    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
            $downloaded = $true; break
        } catch {
            Write-Host "  Download failed: $url" -ForegroundColor Yellow
        }
    }
    if (-not $downloaded) { throw "Android cmdline-tools download failed" }

    $extractDir = Join-Path $env:TEMP "cmdline-tools-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    Remove-Item $zipPath -Force

    $destCmdline = Join-Path $AndroidSdk "cmdline-tools"
    if (Test-Path $destCmdline) { Remove-Item $destCmdline -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $destCmdline "latest") | Out-Null
    Move-Item (Join-Path $extractDir "cmdline-tools\*") (Join-Path $destCmdline "latest") -Force
    Remove-Item $extractDir -Recurse -Force

    Write-Host "  Installing SDK components (~2-3 GB, please wait)..."
    $yes = ("y`n" * 50)
    foreach ($pkg in $SdkPackages) {
        Write-Host "    -> $pkg"
        $yes | & $sdkmanager --sdk_root=$AndroidSdk $pkg 2>&1 | Out-Host
    }
    $yes | & $sdkmanager --sdk_root=$AndroidSdk --licenses 2>&1 | Out-Host
    Write-Ok "Android SDK ready: $AndroidSdk"
}

function Test-NativeLibs {
    $required = @("libluajit.so", "liblove.so", "libSDL3.so")
    $missing = $required | Where-Object { -not (Test-Path (Join-Path $JniLibsDir $_)) }
    if ($missing) {
        Write-Fail "Missing native libs: $($missing -join ', ')"
        return $false
    }
    Write-Ok "Native libs OK"
    return $true
}

function Apply-EnvVars {
    Set-UserEnv "ANDROID_HOME" $AndroidSdk
    Set-UserEnv "ANDROID_SDK_ROOT" $AndroidSdk
    Set-UserEnv "FLUTTER_ROOT" $FlutterDir
    $javaHome = Find-JavaHome
    if ($javaHome) {
        Set-UserEnv "JAVA_HOME" $javaHome
        Add-UserPath (Join-Path $javaHome "bin")
    }
    Add-UserPath (Join-Path $FlutterDir "bin")
    Add-UserPath (Join-Path $AndroidSdk "platform-tools")
    Add-UserPath (Join-Path $AndroidSdk "cmdline-tools\latest\bin")
    Refresh-Path
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Android DIY Sandbox - Setup" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "Project: $ProjectRoot"
Write-Host "Tools:   $DevRoot"
Write-Host ""
Write-Host "Tip: re-run this script anytime to resume." -ForegroundColor Gray

try {
    Write-Step "Check winget"
    if (-not (Test-Command winget)) { throw "winget not found. Install App Installer from Microsoft Store." }
    Write-Ok "winget OK"

    Write-Step "Install Git"
    if (-not (Test-Command git)) {
        Invoke-WingetInstall "Git.Git" "Git"
        Refresh-Path
    }
    if (-not (Test-Command git)) {
        throw "Git installed but not found in PATH. Restart terminal and re-run setup.bat."
    }
    Write-Ok "Git OK"

    Write-Step "Install JDK 17 (portable zip)"
    Install-JdkZip
    $javaHome = Find-JavaHome
    if (-not $javaHome) { throw "JDK 17 not found after install" }
    Write-Ok "JAVA_HOME = $javaHome"

    Write-Step "Install Flutter SDK"
    Install-Flutter

    Write-Step "Install Android SDK + NDK"
    Install-AndroidSdk

    Write-Step "Configure environment variables"
    Apply-EnvVars
    Write-Ok "ANDROID_HOME = $AndroidSdk"
    Write-Ok "FLUTTER_ROOT = $FlutterDir"

    Write-Step "Check native libraries"
    Test-NativeLibs | Out-Null

    Write-Step "flutter pub get"
    Set-Location $ProjectRoot
    $flutter = Join-Path $FlutterDir "bin\flutter.bat"
    & $flutter pub get 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
    Write-Ok "Dependencies OK"

    Write-Step "Precache Flutter Android engine"
    & $flutter precache --android 2>&1 | Out-Host

    Write-Step "Accept Android licenses"
    $yes = ("y`n" * 30)
    $yes | & $flutter doctor --android-licenses 2>&1 | Out-Host

    Write-Step "flutter doctor"
    & $flutter doctor -v 2>&1 | Out-Host

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Setup complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next: double-click build.bat" -ForegroundColor Cyan
    Write-Host ""

    if (-not $SkipBuild) {
        Write-Step "Build debug APK"
        & "$PSScriptRoot\build-apk.ps1" -BuildType debug
    }
} catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    Write-Host "Re-run setup.bat to resume. Already-installed steps will be skipped." -ForegroundColor Yellow
    exit 1
}