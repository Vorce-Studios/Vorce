#!/usr/bin/env pwsh

# Script to update Dependabot dependencies in Cargo.toml files
# This extracts dependency information from Dependabot PRs and updates the files directly

# List of Dependabot PRs to process with their target versions
$dependabotUpdates = @{
    "chrono" = @{
        oldVersion = "0.4.44"
        newVersion = "0.4.45"
        targetFile = "crates/vorce-io/Cargo.toml"
    }
    "glam" = @{
        oldVersion = "0.33.0"
        newVersion = "0.33.1"
        targetFile = "crates/vorce-io/Cargo.toml"
    }
    "grafton-ndi" = @{
        oldVersion = "0.12.0"
        newVersion = "0.13.0"
        targetFile = "crates/vorce-core/Cargo.toml"
    }
    "sysinfo" = @{
        oldVersion = "0.39.2"
        newVersion = "0.39.3"
        targetFile = "crates/vorce-io/Cargo.toml"
    }
    "hyper" = @{
        oldVersion = "1.9.0"
        newVersion = "1.10.1"
        targetFile = "crates/vorce-io/Cargo.toml"
    }
    "tobj" = @{
        oldVersion = "4.0.3"
        newVersion = "4.0.4"
        targetFile = "crates/vorce-core/Cargo.toml"
    }
    "http" = @{
        oldVersion = "1.4.0"
        newVersion = "1.4.2"
        targetFile = "crates/vorce-io/Cargo.toml"
    }
    "cc" = @{
        oldVersion = "1.2.62"
        newVersion = "1.2.64"
        targetFile = "crates/vorce-core/Cargo.toml"
    }
    "uuid" = @{
        oldVersion = "1.23.1"
        newVersion = "1.23.3"
        targetFile = "crates/vorce-core/Cargo.toml"
    }
    "cbindgen" = @{
        oldVersion = "0.29.2"
        newVersion = "0.29.4"
        targetFile = "crates/vorce-ffi/Cargo.toml"
    }
}

foreach ($dep in $dependabotUpdates.GetEnumerator()) {
    $name = $dep.Key
    $oldVer = $dep.Value.oldVersion
    $newVer = $dep.Value.newVersion
    $targetFile = $dep.Value.targetFile

    Write-Host "Updating $name from $oldVer to $newVer in $targetFile"

    # Check if the file exists
    if (-not (Test-Path $targetFile)) {
        Write-Host "ERROR: File $targetFile not found!" -ForegroundColor Red
        continue
    }

    # Read the current file
    $content = Get-Content $targetFile -Raw

    # Check if the old version exists
    if ($content -match "$name\s*=\s*""$oldVer""") {
        # Update the version
        $newContent = $content -replace "$name\s*=\s*""$oldVer""", "$name = `"$newVer`""
        $newContent | Out-File $targetFile -Encoding UTF8

        Write-Host "Updated $name to $newVersion" -ForegroundColor Green

        # Verify the update
        $checkContent = Get-Content $targetFile -Raw
        if ($checkContent -match "$name\s*=\s*""$newVer""") {
            Write-Host "SUCCESS: Version update verified" -ForegroundColor Green
        } else {
            Write-Host "ERROR: Version update failed!" -ForegroundColor Red
        }
    } else {
        Write-Host "WARNING: Could not find $name version $oldVer in $targetFile" -ForegroundColor Yellow
        # Show what version is actually there
        if ($content -match "$name\s*=\s*""([0-9.]+)""") {
            $currentVersion = $matches[1]
            Write-Host "Found version: $currentVersion" -ForegroundColor Yellow
        }
    }

    Write-Host ""
}

Write-Host "Dependabot dependency updates complete!" -ForegroundColor Cyan