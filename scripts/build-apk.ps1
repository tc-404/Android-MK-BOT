# Quick APK build script (run after setup)
param(
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$DevRoot = 'C:\dev'
$buildRoot = Join-Path $DevRoot 'Android-DIY-Sandbox-master'

# Refresh PATH
$machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$user    = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machine;$user"

$flutterRoot = 'C:\dev\flutter'
$javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
$androidHome = 'C:\dev\Android\Sdk'
if ($javaHome) { $env:Path = "$javaHome\bin;$env:Path" }
$env:Path = "$flutterRoot\bin;$androidHome\platform-tools;$androidHome\cmdline-tools\latest\bin;$env:Path"
$env:FLUTTER_ROOT = $flutterRoot
$env:ANDROID_HOME = $androidHome

if (-not (Test-Path $buildRoot)) {
    throw "Project junction missing: $buildRoot`nRun setup.bat first."
}

Push-Location $buildRoot
try {
    Write-Host "Syncing source from workspace to $buildRoot ..." -ForegroundColor DarkGray
    $srcRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    if (-not (Test-Path $srcRoot)) {
        $srcRoot = 'c:\Users\筱筱\Desktop\Android-DIY-Sandbox-master'
    }
    if ((Resolve-Path $srcRoot).Path -ne (Resolve-Path $buildRoot).Path) {
        robocopy "$srcRoot\lib" "$buildRoot\lib" /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        robocopy "$srcRoot\assets" "$buildRoot\assets" /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        Copy-Item -Force "$srcRoot\lib\main.dart" "$buildRoot\lib\main.dart" -ErrorAction SilentlyContinue
    }

    $mode = if ($Release) { 'release' } else { 'debug' }
    Write-Host "Building $mode APK from $buildRoot ..." -ForegroundColor Cyan

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    flutter build apk --$mode --flavor normal --target-platform android-arm64 --no-tree-shake-icons
    $ErrorActionPreference = $prevEap

    if ($LASTEXITCODE -ne 0) { throw "build failed exit $LASTEXITCODE" }

    $apk = Get-ChildItem "build\app\outputs\flutter-apk\app-normal-*.apk" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $apk) {
        $apk = Get-ChildItem "android\app\outputs\apk\normal\$mode\*.apk" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($apk) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $destName = if ($apk.Name -match '^Android-DIY-Sandbox') { $apk.Name } else {
            $ver = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
            if ($ver -match '^(\d+\.\d+\.\d+)') { $ver = $Matches[1] } else { $ver = '0.0.0' }
            "Android-DIY-Sandbox-v$ver-$mode.apk"
        }
        $dest = Join-Path $desktop $destName
        Copy-Item -Force $apk.FullName $dest
        Write-Host ""
        Write-Host "APK: $($apk.FullName)" -ForegroundColor Green
        Write-Host "Desktop: $dest" -ForegroundColor Green
        Write-Host "Size: $([math]::Round($apk.Length / 1MB, 1)) MB" -ForegroundColor Green
    }
} finally {
    Pop-Location
}
