# self-hosted-post-merge.ps1
# This script runs on the self-hosted Windows runner to validate the build and run GPU tests.

$ErrorActionPreference = "Stop"

$repoRoot = Get-Item $PSScriptRoot | Select-Object -ExpandProperty Parent | Select-Object -ExpandProperty Parent | Select-Object -ExpandProperty FullName
Write-Host "Repo Root: $repoRoot"

function Assert-Command($Name, $HelpText) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' not found. $HelpText"
    }
}

Assert-Command -Name "git" -HelpText "Install Git for Windows."
Assert-Command -Name "cargo" -HelpText "Install Rust and ensure cargo is in PATH."

# vcpkg detection
if (-not $env:VCPKG_ROOT) {
    $searchPaths = @(
        (Join-Path $repoRoot "vcpkg"),
        "C:\vcpkg",
        "D:\vcpkg",
        "C:\src\vcpkg",
        "C:\tools\vcpkg"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path (Join-Path $p "vcpkg.exe")) {
            $env:VCPKG_ROOT = $p
            Write-Host "Detected vcpkg at: $p"
            break
        }
    }
}

if (-not $env:VCPKG_ROOT -or -not (Test-Path $env:VCPKG_ROOT)) {
    throw "vcpkg was not found. Please set VCPKG_ROOT or install vcpkg in a standard location."
}

if (-not $env:VCPKG_DEFAULT_TRIPLET) { $env:VCPKG_DEFAULT_TRIPLET = "x64-windows" }
$vcpkgExe = Join-Path $env:VCPKG_ROOT "vcpkg.exe"

# LLVM / Clang for bindgen
if (-not $env:LIBCLANG_PATH) {
    $llvmPaths = @("C:\Program Files\LLVM\bin", "C:\Program Files (x86)\LLVM\bin")
    foreach ($p in $llvmPaths) {
        if (Test-Path $p) {
            $env:LIBCLANG_PATH = $p
            $env:Path = "$p;$env:Path"
            Write-Host "Detected LLVM at: $p"
            break
        }
    }
}

# Ensure artifacts dir exists
$artifactsDir = Join-Path $repoRoot "artifacts\visual-capture"
if (-not (Test-Path $artifactsDir)) {
    New-Item -ItemType Directory -Force -Path $artifactsDir
}

Write-Host "--- Starting Build & Test ---"
cargo build --workspace --release

# Run Visual Automation if enabled
if ($env:MAPFLOW_SELF_HOSTED_RUN_VISUAL_AUTOMATION -eq "true") {
    Write-Host "Running Visual Automation Tests..."
    # We use cargo test which calls the harness
    cargo test -p mapmap --test visual_capture_tests --release -- --ignored --nocapture
}

# Run GPU Tests if enabled
if ($env:MAPFLOW_SELF_HOSTED_RUN_IGNORED_GPU_TESTS -eq "true") {
    Write-Host "Running GPU-bound tests..."
    cargo test --workspace --release -- --ignored
}

Write-Host "Validation completed successfully."
