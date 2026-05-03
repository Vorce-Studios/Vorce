<#
.SYNOPSIS
    Windows packaging smoke test: validates that all artifacts declared in the
    WiX installer manifest (main.wxs) are present in the release output directory.

.DESCRIPTION
    Checks for:
    - Vorce.exe (main executable)
    - All FFmpeg / runtime DLLs listed in main.wxs
    - The application icon (.ico) referenced by the installer

    Exits with code 0 on success, 1 on any missing artifact.

.PARAMETER BinDir
    Path to the release binary directory (default: target\release).

.PARAMETER SkipDlls
    If set, skip DLL presence checks (use when building without FFmpeg features).
#>
param(
    [string]$BinDir = "target\release",
    [switch]$SkipDlls
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$binPath  = Join-Path $root $BinDir
$iconPath = Join-Path $root "resources\app_icons\Vorce_Logo_LQ-Full.ico"

$failures = @()

# --- Executable ---
$exe = Join-Path $binPath "Vorce.exe"
if (-not (Test-Path $exe)) {
    $failures += "MISSING executable: $exe"
} else {
    Write-Host "[OK] Vorce.exe"
}

# --- Icon ---
if (-not (Test-Path $iconPath)) {
    $failures += "MISSING icon: $iconPath"
} else {
    Write-Host "[OK] icon: Vorce_Logo_LQ-Full.ico"
}

# --- FFmpeg / runtime DLLs (as declared in crates/vorce/wix/main.wxs) ---
$requiredDlls = @(
    "avcodec-61.dll",
    "avdevice-61.dll",
    "avfilter-10.dll",
    "avformat-61.dll",
    "avutil-59.dll",
    "swresample-5.dll",
    "swscale-8.dll",
    "pkgconf-7.dll"
)

if ($SkipDlls) {
    Write-Host "[SKIP] DLL checks skipped (SkipDlls flag set)"
} else {
    foreach ($dll in $requiredDlls) {
        $dllPath = Join-Path $binPath $dll
        if (-not (Test-Path $dllPath)) {
            $failures += "MISSING DLL: $dll (expected at $dllPath)"
        } else {
            Write-Host "[OK] $dll"
        }
    }
}

# --- Result ---
if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "SMOKE TEST FAILED - $($failures.Count) artifact(s) missing:" -ForegroundColor Red
    foreach ($f in $failures) {
        Write-Host "  $f" -ForegroundColor Red
    }
    exit 1
}

Write-Host ""
Write-Host "SMOKE TEST PASSED - all required packaging artifacts present." -ForegroundColor Green
exit 0
