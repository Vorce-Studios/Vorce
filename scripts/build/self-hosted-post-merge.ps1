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
    $parentDir = Split-Path -Parent $repoRoot
    $grandParentDir = Split-Path -Parent $parentDir

    $candidates = @(
        (Join-Path $repoRoot "vcpkg"),
        (Join-Path $parentDir "vcpkg"),
        (Join-Path $grandParentDir "vcpkg"),
        "C:\vcpkg",
        "D:\vcpkg",
        "C:\src\vcpkg",
        "C:\tools\vcpkg",
        "$HOME\vcpkg"
    )
    foreach ($p in $candidates) {
        if (-not $p) { continue }
        # Check if drive exists before Join-Path to avoid DriveNotFoundException
        if ($p.Contains(":")) {
            $drive = $p.Split(":")[0] + ":"
            if (-not (Test-Path $drive)) { continue }
        }

        if (Test-Path (Join-Path $p "vcpkg.exe")) {
            $env:VCPKG_ROOT = $p
            Write-Host "Detected vcpkg at: $p"
            break
        }
    }
}

# Fallback: Clone vcpkg if still not found
if (-not $env:VCPKG_ROOT -or -not (Test-Path $env:VCPKG_ROOT)) {
    Write-Warning "vcpkg not found in candidates. Cloning to $repoRoot\vcpkg as fallback..."
    $env:VCPKG_ROOT = Join-Path $repoRoot "vcpkg"
    if (-not (Test-Path $env:VCPKG_ROOT)) {
        git clone --depth 1 https://github.com/microsoft/vcpkg.git $env:VCPKG_ROOT
    }
}

$vcpkgExe = Join-Path $env:VCPKG_ROOT "vcpkg.exe"
$bootstrapScript = Join-Path $env:VCPKG_ROOT "bootstrap-vcpkg.bat"

# Bootstrap if executable is missing
if (-not (Test-Path $vcpkgExe)) {
    if (Test-Path $bootstrapScript) {
        Write-Host "Bootstrapping vcpkg..."
        Push-Location $env:VCPKG_ROOT
        & .\bootstrap-vcpkg.bat
        Pop-Location
    } else {
        throw "vcpkg was not found and could not be bootstrapped at $($env:VCPKG_ROOT)."
    }
}

if (-not $env:VCPKG_DEFAULT_TRIPLET) { $env:VCPKG_DEFAULT_TRIPLET = "x64-windows" }

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

Write-Host "--- Starting Build (Limited to 4 threads) ---"
cargo build --workspace --release -j 4

# Helper: run a test command, print header, propagate errors
function Invoke-TestSuite {
    param([string]$Label, [string]$Command)
    Write-Host ""
    Write-Host "--- $Label ---"
    Invoke-Expression $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Test suite '$Label' failed (exit code $LASTEXITCODE)."
    }
}

# ── UI & Automation Tests ─────────────────────────────────────────────────────
# timeline_automation_tests  : TimelineV2 module switching (no GPU, no --ignored)
# app_automation_tests        : Full E2E app launch (requires GPU + display → --ignored)
if ($env:MAPFLOW_RUN_UI_TESTS -eq "true") {
    Invoke-TestSuite "UI Tests – timeline_automation" `
        "cargo test -p mapmap-ui --test timeline_automation_tests --release -j 4 -- --nocapture"

    Invoke-TestSuite "UI Tests – app_automation (GPU+display)" `
        "cargo test -p mapmap --test app_automation_tests --release -j 4 -- --ignored --nocapture"
}

# ── Core Logic Tests ──────────────────────────────────────────────────────────
# trigger_tests / trigger_system_tests : MIDI, OSC, keyboard, audio-FFT triggers
# module_tests                          : ModuleManager CRUD, connections, sockets
# trackline_tests / layer_tests / assignment_tests / module_playback_tests
# project_tests (mapmap-io)             : Project I/O round-trip
if ($env:MAPFLOW_RUN_CORE_TESTS -eq "true") {
    Invoke-TestSuite "Core Tests – triggers" `
        "cargo test -p mapmap-core --test trigger_tests --test trigger_system_tests --test trigger_logic_tests --release -j 4 -- --nocapture"

    Invoke-TestSuite "Core Tests – modules" `
        "cargo test -p mapmap-core --test module_tests --test module_playback_tests --test module_coverage_tests --release -j 4 -- --nocapture"

    Invoke-TestSuite "Core Tests – trackline / layer / assignment" `
        "cargo test -p mapmap-core --test trackline_tests --test layer_tests --test assignment_tests --release -j 4 -- --nocapture"

    Invoke-TestSuite "Core Tests – project I/O" `
        "cargo test -p mapmap-io --test project_tests --release -j 4 -- --nocapture"
}

# ── Integration Tests ─────────────────────────────────────────────────────────
# effect_chain_integration_tests : wgpu texture passthrough (GPU, --ignored)
# multi_output_tests              : RenderOp multi-output (--ignored, marked for refactor)
if ($env:MAPFLOW_RUN_INTEGRATION_TESTS -eq "true") {
    Invoke-TestSuite "Integration Tests – effect_chain_integration (GPU)" `
        "cargo test -p mapmap-render --test effect_chain_integration_tests --release -j 4 -- --ignored --nocapture"

    Invoke-TestSuite "Integration Tests – multi_output (GPU)" `
        "cargo test -p mapmap-render --test multi_output_tests --release -j 4 -- --ignored --nocapture"
}

# ── Performance & GPU Tests ───────────────────────────────────────────────────
# effect_chain_tests  : wgpu renderer creation + invert effect (GPU, --ignored)
# visual_capture_tests: pixel-level visual regression (GPU + desktop session, --ignored)
# run_performance_benchmark.py : MapFlow --mode automation frame-timing benchmark
if ($env:MAPFLOW_RUN_PERFORMANCE_TESTS -eq "true") {
    Invoke-TestSuite "Performance Tests – effect_chain GPU" `
        "cargo test -p mapmap-render --test effect_chain_tests --release -j 4 -- --ignored --nocapture"

    Write-Host ""
    Write-Host "--- Performance Benchmark – MapFlow automation mode ---"
    $pythonCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }
    $benchScript = Join-Path $repoRoot "scripts\dev-tools\run_performance_benchmark.py"
    $benchArgs = @("$benchScript", "--iterations", "3", "--frames", "300")
    if ($env:MAPFLOW_PERFORMANCE_THRESHOLD) {
        $benchArgs += @("--threshold", $env:MAPFLOW_PERFORMANCE_THRESHOLD, "--fail-on-regression")
    }
    & $pythonCmd @benchArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Performance benchmark failed (exit code $LASTEXITCODE)."
    }
}

if ($env:MAPFLOW_SELF_HOSTED_RUN_VISUAL_AUTOMATION -eq "true") {
    $env:MAPFLOW_VISUAL_CAPTURE_OUTPUT_DIR = Join-Path $repoRoot "artifacts\visual-capture"
    Invoke-TestSuite "Visual Automation – visual_capture (GPU+desktop)" `
        "cargo test -p mapmap --no-default-features --test visual_capture_tests --release -j 4 -- --ignored --nocapture"
}

# Run GPU Tests if enabled (Workspace-wide)
if ($env:MAPFLOW_SELF_HOSTED_RUN_IGNORED_GPU_TESTS -eq "true") {
    Write-Host "Running GPU-bound tests..."
    cargo test --workspace --release -- --ignored
}

Write-Host ""
Write-Host "Validation completed successfully."
