# Build Flutter Android APK
# Usage: .\build-utils\build-android.ps1 [-EnvFile .env]

param(
    [string]$EnvFile = ".env"
)

Write-Host "Building Flutter Android APK..." -ForegroundColor Green

# Verificar que estamos en el directorio correcto
$projectRoot = Split-Path -Parent $PSScriptRoot

# Build release APK
Write-Host "Building Android release..." -ForegroundColor Cyan
Set-Location $projectRoot
$envArg = ""
if (Test-Path "$projectRoot\$EnvFile") {
    Write-Host "Loading environment from $EnvFile..." -ForegroundColor Cyan
    $envArg = "--dart-define-from-file=$EnvFile"
} else {
    Write-Host "Env file not found: $EnvFile" -ForegroundColor Yellow
}

# One APK instead of a universal one: every device NeoStation targets is arm64,
# but plain `flutter build apk` packs armeabi-v7a and x86_64 in as well. Both
# flags are needed: --target-platform only drops the engine and AOT libs, while
# --split-per-abi sets abiFilters, which is what drops the plugin natives
# Gradle packages for every ABI.
flutter build apk --release --split-per-abi --target-platform android-arm64 $envArg

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error during build" -ForegroundColor Red
    exit 1
}

# Obtener versión del pubspec.yaml
$version = (Select-String -Path "$projectRoot\pubspec.yaml" -Pattern "^version:\s*(.+)" | ForEach-Object { $_.Matches.Groups[1].Value }).Trim()

# Crear directorio de salida
Write-Host "Creating output directory..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path "$projectRoot\release" -Force | Out-Null

# Copiar y renombrar APK
Write-Host "Copying APK to release..." -ForegroundColor Cyan
# --split-per-abi renames the output to carry the ABI.
$apkDir = "$projectRoot\build\app\outputs\flutter-apk"
$sourceApk = "$apkDir\app-arm64-v8a-release.apk"
$destApk = "$projectRoot\release\neostation-android-arm64-v8a-$version.apk"

if (Test-Path $sourceApk) {
    Copy-Item -Path $sourceApk -Destination $destApk -Force
    
    Write-Host ""
    Write-Host "Build completado!" -ForegroundColor Green
    Write-Host "Resultado en: release\" -ForegroundColor Cyan
    Get-ChildItem -Path "$projectRoot\release" -Filter "*.apk" | Format-Table Name, @{Name="Size (MB)";Expression={[math]::Round($_.Length/1MB, 2)}}, LastWriteTime
} else {
    Write-Host "No arm64-v8a release APK found in: $apkDir" -ForegroundColor Red
    if (Test-Path $apkDir) {
        Get-ChildItem -Path $apkDir | Select-Object -ExpandProperty Name
    } else {
        Write-Host "  (directory does not exist)"
    }
    exit 1
}
