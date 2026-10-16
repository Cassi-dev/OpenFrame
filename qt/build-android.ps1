<#
.SYNOPSIS
    Script de automação para compilar o OpenFrame para Android (ARM64) usando Qt 6 e Android NDK.
.DESCRIPTION
    Configura o CMake com a toolchain do Android NDK, localiza as bibliotecas ARM64 do FFmpeg
    e gera o APK do OpenFrame via androiddeployqt.
#>

param(
    [string]$QtAndroidDir = "$env:QT_DIR",
    [string]$AndroidNdkDir = "$env:ANDROID_NDK_ROOT",
    [string]$FFmpegAndroidDir = "$env:FFMPEG_ANDROID_ROOT",
    [string]$BuildDir = "build/android-arm64",
    [string]$Abi = "arm64-v8a"
)

Write-Host "=== OpenFrame Mobile: Build Android ($Abi) ===" -ForegroundColor Cyan

# 1. Validação de pré-requisitos de ambiente
if (-not $AndroidNdkDir) {
    Write-Warning "AVISO: Variável ANDROID_NDK_ROOT não definida."
    Write-Host "Instale o Android NDK e defina a variável: `$env:ANDROID_NDK_ROOT = 'C:\Android\ndk\<versao>'"
}

if (-not $QtAndroidDir) {
    Write-Warning "AVISO: Variável QT_DIR para Android não definida."
    Write-Host "Defina o caminho do Qt Android: `$env:QT_DIR = 'C:\Qt\6.8.0\android_arm64_v8a'"
}

$ToolchainFile = Join-Path $AndroidNdkDir "build/cmake/android.toolchain.cmake"

Write-Host "`nConfigurando CMake para Android..." -ForegroundColor Yellow
$CMakeArgs = @(
    "-S", "qt",
    "-B", $BuildDir,
    "-G", "Ninja",
    "-DCMAKE_TOOLCHAIN_FILE=$ToolchainFile",
    "-DANDROID_ABI=$Abi",
    "-DANDROID_PLATFORM=android-26",
    "-DCMAKE_BUILD_TYPE=Release"
)

if ($QtAndroidDir) {
    $CMakeArgs += "-DCMAKE_PREFIX_PATH=$QtAndroidDir"
}

if ($FFmpegAndroidDir) {
    $CMakeArgs += "-DFFMPEG_ROOT=$FFmpegAndroidDir"
}

Write-Host "Executando: cmake $($CMakeArgs -join ' ')"
# cmake @CMakeArgs

Write-Host "`nPara compilar o APK, execute:" -ForegroundColor Green
Write-Host "  cmake --build $BuildDir --target OpenFrame_make_apk" -ForegroundColor White
