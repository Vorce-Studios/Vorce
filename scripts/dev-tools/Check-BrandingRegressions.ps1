# Check-BrandingRegressions.ps1
# Verhindert, dass alte Mapflow-Bilder durch fehlerhafte Merges zurückkehren.

$ForbiddenHashes = @(
    "e36e92c00e58847b72ab8aa2247740cb6baa08c3", # MapFlow_Logo_HQ-Full-L.png
    "cc155d0feace6429513aabacf76b9fee3454c201", # MapFlow_Logo_HQ-Full-L.webp
    "92658981ac88bd2f28fa50f1a07c1569626f349f", # MapFlow_Logo_HQ-Full-M.png
    "a57d021f55fdaee8689ef6c1486d4152630bd69c", # MapFlow_Logo_HQ-Full-M.webp
    "abb54fea8b98cdcc902822676694a64a02bbd2e1", # MapFlow_Logo_LQ-Full.icns
    "8458fe2c2a9e765fb69c901698ebdb6814269455", # MapFlow_Logo_LQ-Full.ico
    "55ea17ab81f6ee0604e2bf91848a1ecd39ba6550", # mapflow.icns
    "d005738c1ed35077f3280199d2e060d79a35c01e", # mapflow.ico
    "f5472fdeda410c83130f3d34dcc0b0e52f078fbd"  # mapflow.png
)

Write-Host "Searching for branding regressions (old Mapflow content)..."
$FoundIssues = 0

# Check all files in repository via git ls-tree
$Tree = git ls-tree -r HEAD
foreach ($line in $Tree) {
    if ($line -match '(?<mode>\d+) (?<type>\w+) (?<hash>[0-9a-f]+)\s+(?<path>.*)') {
        $hash = $Matches['hash']
        $path = $Matches['path']

        if ($ForbiddenHashes -contains $hash) {
            Write-Host "ERROR: Obsolete Mapflow content found in: $path"
            Write-Host "   (Hash: $hash)"
            $FoundIssues++
        }
    }
}

if ($FoundIssues -gt 0) {
    Write-Host ""
    Write-Host "REGRESSION DETECTED! Found $FoundIssues obsolete files."
    Write-Host "Please restore the correct Vorce branding assets."
    exit 1
} else {
    Write-Host "Success: No old branding found. Everything clean."
    exit 0
}
