# Android DIY Sandbox - Windows one-click setup
# Usage: double-click setup.bat
#        setup.bat -Build          (setup + build debug APK)
#        setup.bat -Build -Release (setup + build release APK)

param(
    [switch]$Build,
    [switch]$Release,
    [switch]$SkipWinget
)

$ErrorActionPreference = 'Stop'

# All tool paths under C:\dev (ASCII-only) to avoid Gradle/NDK bugs with Chinese Windows usernames.
$DevRoot     = 'C:\dev'
$FlutterDir  = Join-Path $DevRoot 'flutter'
$SdkRoot     = Join-Path $DevRoot 'Android\Sdk'
$SrcRoot     = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$BuildRoot   = Join-Path $DevRoot 'Android-DIY-Sandbox-master'

function Write-Step([string]$Msg) { Write-Host ""; Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Skip([string]$Msg) { Write-Host "  [SKIP] $Msg" -ForegroundColor Yellow }

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
    foreach ($dir in @(
        "$env:JAVA_HOME\bin",
        "$FlutterDir\bin",
        "$SdkRoot\platform-tools",
        "$SdkRoot\cmdline-tools\latest\bin",
        'C:\Program Files\Git\cmd'
    )) {
        if ($dir -and (Test-Path $dir) -and ($env:Path -notlike "*$dir*")) {
            $env:Path = "$dir;$env:Path"
        }
    }
}

function Set-UserEnv([string]$Name, [string]$Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path "Env:$Name" -Value $Value
}

function Add-UserPath([string]$Dir) {
    if (-not (Test-Path $Dir)) { return }
    $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($cur -split ';' -contains $Dir) { return }
    [Environment]::SetEnvironmentVariable('Path', "$cur;$Dir", 'User')
    if ($env:Path -notlike "*$Dir*") { $env:Path = "$Dir;$env:Path" }
}

function Install-Winget([string]$Id, [string]$Label) {
    if ($SkipWinget) { Write-Skip "winget: $Label"; return }
    $list = winget list --id $Id -e 2>&1 | Out-String
    if ($list -match [regex]::Escape($Id)) { Write-Skip "$Label already installed"; return }
    Write-Host "  installing $Label ..."
    winget install -e --id $Id --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -gt 1) { throw "winget failed: $Label" }
    Write-Ok "$Label installed"
}

function Find-JavaHome {
    foreach ($p in @(
        "$env:ProgramFiles\Eclipse Adoptium\jdk-17*",
        "$env:ProgramFiles\Microsoft\jdk-17*"
    )) {
        $f = Get-Item $p -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}

function Install-Flutter {
    New-Item -ItemType Directory -Path $DevRoot -Force | Out-Null
    $bat = Join-Path $FlutterDir 'bin\flutter.bat'
    if (Test-Path $bat) {
        Write-Skip "Flutter exists: $FlutterDir"
        Push-Location $FlutterDir; git pull --ff-only 2>$null; Pop-Location
    } else {
        Write-Host "  cloning Flutter to $FlutterDir (about 1GB) ..."
        git clone --depth 1 -b stable https://github.com/flutter/flutter.git $FlutterDir
        if ($LASTEXITCODE -ne 0) { throw 'flutter clone failed' }
        Write-Ok "Flutter cloned"
    }
    Set-UserEnv 'FLUTTER_ROOT' $FlutterDir
    Set-UserEnv 'PUB_HOSTED_URL' 'https://pub.flutter-io.cn'
    Set-UserEnv 'FLUTTER_STORAGE_BASE_URL' 'https://storage.flutter-io.cn'
    Add-UserPath (Join-Path $FlutterDir 'bin')
    Refresh-Path
    & $bat --version
    if ($LASTEXITCODE -ne 0) { throw 'flutter --version failed' }
    Write-Ok "Flutter ready"
}

function Install-AndroidSdk {
    $sdkmanager = Join-Path $SdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path $sdkmanager)) {
        Write-Host "  downloading Android SDK Command-line Tools ..."
        $zip = Join-Path $env:TEMP 'cmdline-tools.zip'
        Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip' -OutFile $zip -UseBasicParsing
        $tmp = Join-Path $env:TEMP 'cmdline-extract'
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive $zip $tmp -Force
        $dest = Join-Path $SdkRoot 'cmdline-tools\latest'
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Move-Item (Join-Path $tmp 'cmdline-tools') $dest
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "Command-line Tools ready"
    } else {
        Write-Skip "Android SDK tools exist"
    }

    Set-UserEnv 'ANDROID_HOME' $SdkRoot
    Set-UserEnv 'ANDROID_SDK_ROOT' $SdkRoot
    Add-UserPath "$SdkRoot\platform-tools"
    Add-UserPath "$SdkRoot\cmdline-tools\latest\bin"
    Refresh-Path

    $pkgs = @(
        'platform-tools', 'platforms;android-35', 'platforms;android-36',
        'build-tools;35.0.0', 'build-tools;28.0.3',
        'ndk;27.0.12077973', 'cmake;3.22.1'
    )
    Write-Host "  installing SDK packages (10+ min first time) ..."
    $yes = ('y' + [Environment]::NewLine) * 50
    $yes | & $sdkmanager --sdk_root=$SdkRoot @pkgs
    $yes | & $sdkmanager --sdk_root=$SdkRoot --licenses 2>&1 | Out-Null
    Write-Ok "Android SDK ready at $SdkRoot"
}

function Sync-Project {
    Write-Host "  syncing project to $BuildRoot ..."
    New-Item -ItemType Directory -Path $DevRoot -Force | Out-Null
    $args = @(
        $SrcRoot, $BuildRoot,
        '/E', '/XD', 'build', '.dart_tool', '.gradle', 'android\.gradle', 'android\app\build',
        '/NFL', '/NDL', '/NJH', '/NJS', '/nc', '/ns', '/np'
    )
    & robocopy @args | Out-Null
    # robocopy exit 0-7 = success
    if ($LASTEXITCODE -gt 7) { throw "robocopy failed exit $LASTEXITCODE" }
    Write-Ok "project synced to $BuildRoot"
}

function Write-LocalProperties {
    $props = Join-Path $BuildRoot 'android\local.properties'
    @(
        'sdk.dir=C:\\dev\\Android\\Sdk'
        'flutter.sdk=C:\\dev\\flutter'
    ) | Set-Content $props -Encoding UTF8
}

function Test-NativeLibs {
    $jni = Join-Path $BuildRoot 'android\app\src\main\jniLibs\arm64-v8a'
    foreach ($f in @('libluajit.so', 'liblove.so', 'libSDL3.so')) {
        if (-not (Test-Path (Join-Path $jni $f))) {
            throw "missing native lib: $f in $jni"
        }
    }
    Write-Ok "native libs OK"
}

function Invoke-ProjectInit {
    Push-Location $BuildRoot
    try {
        Write-LocalProperties
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        flutter config --android-sdk $SdkRoot 2>$null
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
        $yes = ('y' + [Environment]::NewLine) * 50
        $yes | flutter doctor --android-licenses 2>&1 | Out-Null
        flutter doctor -v
        $ErrorActionPreference = $eap
        Write-Ok "project initialized"
    } finally { Pop-Location }
}

function Invoke-BuildApk {
    Push-Location $BuildRoot
    try {
        $mode = if ($Release) { 'release' } else { 'debug' }
        Write-Step "building $mode APK ..."
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        flutter build apk --$mode --flavor normal --target-platform android-arm64 --no-tree-shake-icons
        $ErrorActionPreference = $eap
        if ($LASTEXITCODE -ne 0) { throw 'build failed' }
        $apk = Get-ChildItem "android\app\outputs\apk\normal\$mode\*.apk" | Select-Object -First 1
        if ($apk) {
            Write-Ok "APK: $($apk.FullName) ($([math]::Round($apk.Length/1MB,1)) MB)"
        }
    } finally { Pop-Location }
}

# ── main ──
Write-Host ""
Write-Host "  Android DIY Sandbox - Setup" -ForegroundColor White
Write-Host "  source : $SrcRoot"
Write-Host "  build  : $BuildRoot"
Write-Host ""

Write-Step "prerequisites"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Install-Winget 'Git.Git' 'Git'
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget required - install App Installer from Microsoft Store'
}
Write-Ok "git + winget OK"

Write-Step "JDK 17"
Install-Winget 'EclipseAdoptium.Temurin.17.JDK' 'Temurin JDK 17'
$jh = Find-JavaHome
if (-not $jh) { throw 'JDK 17 not found' }
Set-UserEnv 'JAVA_HOME' $jh
Add-UserPath "$jh\bin"
Refresh-Path
Write-Ok "JAVA_HOME=$jh"

Write-Step "Flutter SDK"
Install-Flutter

Write-Step "Android SDK + NDK"
Install-AndroidSdk

Write-Step "sync project to C:\dev"
Sync-Project

Write-Step "check native libs"
Test-NativeLibs

Write-Step "init project"
Invoke-ProjectInit

if ($Build) { Invoke-BuildApk }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Work directory : $BuildRoot" -ForegroundColor Yellow
Write-Host "  Build debug APK: double-click build-apk.bat" -ForegroundColor White
Write-Host "  Or re-run      : setup.bat -Build" -ForegroundColor White
Write-Host ""
