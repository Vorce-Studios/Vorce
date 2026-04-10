Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\..\..') 'scripts\jules\jules-github.ps1')

function Get-VorceStudiosPluginSourceDefinitions {
    $paths = Get-VorceStudiosPaths

    return @(
        @{
            PluginId = 'paperclip-plugin-github-issues'
            SourceName = 'paperclip-plugin-github-issues'
            PackageName = 'paperclip-plugin-github-issues'
            Repository = 'https://github.com/mvanhorn/paperclip-plugin-github-issues.git'
            LocalPath = Join-Path $paths.PluginSourcesDir 'paperclip-plugin-github-issues'
        }
        @{
            PluginId = 'paperclip-chat'
            SourceName = 'paperclip-plugin-chat'
            PackageName = '@paperclipai/plugin-chat'
            Repository = 'https://github.com/webprismdevin/paperclip-plugin-chat.git'
            LocalPath = Join-Path $paths.PluginSourcesDir 'paperclip-plugin-chat'
        }
        @{
            PluginId = 'tomismeta.paperclip-aperture'
            SourceName = 'paperclip-aperture'
            PackageName = '@tomismeta/paperclip-aperture'
            Repository = 'https://github.com/tomismeta/paperclip-aperture.git'
            LocalPath = Join-Path $paths.PluginSourcesDir 'paperclip-aperture'
        }
        @{
            PluginId = 'agent-analytics.paperclip-live-analytics-plugin'
            SourceName = 'paperclip-live-analytics-plugin'
            PackageName = '@agent-analytics/paperclip-live-analytics-plugin'
            Repository = 'https://github.com/Agent-Analytics/paperclip-live-analytics-plugin.git'
            LocalPath = Join-Path $paths.PluginSourcesDir 'paperclip-live-analytics-plugin'
        }
        @{
            PluginId = 'paperclip-plugin-telegram'
            SourceName = 'paperclip-plugin-telegram'
            PackageName = 'paperclip-plugin-telegram'
            Repository = 'https://github.com/mvanhorn/paperclip-plugin-telegram.git'
            LocalPath = Join-Path $paths.PluginSourcesDir 'paperclip-plugin-telegram'
        }
    )
}

function Get-VorceStudiosPluginSourceDefinition {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    return @(
        Get-VorceStudiosPluginSourceDefinitions |
            Where-Object {
                ([string]$_.PluginId -eq $PluginId) -or
                ([string]$_.SourceName -eq $PluginId) -or
                ([string]$_.PackageName -eq $PluginId)
            } |
            Select-Object -First 1
    )[0]
}

function Set-VorceStudiosVendorFileContent {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-VorceStudiosVendorOverrideRoot {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    return (Join-Path (Join-Path $PSScriptRoot '..') ("vendor-overrides\{0}" -f $PluginId))
}

function Sync-VorceStudiosVendorOverrideFiles {
    param(
        [Parameter(Mandatory)][string]$PluginId,
        [Parameter(Mandatory)][string]$LocalPath
    )

    $overrideRoot = Get-VorceStudiosVendorOverrideRoot -PluginId $PluginId
    if (-not (Test-Path -LiteralPath $overrideRoot)) {
        return @()
    }

    $updated = New-Object System.Collections.Generic.List[string]
    foreach ($sourceFile in @(Get-ChildItem -Path $overrideRoot -Recurse -File)) {
        $relativePath = [System.IO.Path]::GetRelativePath($overrideRoot, $sourceFile.FullName)
        $targetPath = Join-Path $LocalPath $relativePath
        $newContent = Get-Content -LiteralPath $sourceFile.FullName -Raw -ErrorAction Stop
        $currentContent = ''
        if (Test-Path -LiteralPath $targetPath) {
            $currentContent = Get-Content -LiteralPath $targetPath -Raw -ErrorAction Stop
        }

        if ($currentContent -eq $newContent) {
            continue
        }

        Set-VorceStudiosVendorFileContent -Path $targetPath -Content $newContent
        $updated.Add($targetPath) | Out-Null
    }

    return $updated.ToArray()
}

function Update-VorceStudiosVendorPackageJson {
    param(
        [Parameter(Mandatory)][string]$PackageJsonPath,
        [Parameter(Mandatory)][scriptblock]$Mutator
    )

    if (-not (Test-Path -LiteralPath $PackageJsonPath)) {
        throw "package.json nicht gefunden: $PackageJsonPath"
    }

    $raw = Get-Content -LiteralPath $PackageJsonPath -Raw -ErrorAction Stop
    $package = $raw | ConvertFrom-Json -AsHashtable
    & $Mutator $package
    $updated = $package | ConvertTo-Json -Depth 100
    if ($updated -ne $raw) {
        Set-VorceStudiosVendorFileContent -Path $PackageJsonPath -Content $updated
    }
}

function Get-VorceStudiosVendorPackageManifestInfo {
    param(
        [Parameter(Mandatory)][string]$LocalPath
    )

    $packageJsonPath = Join-Path $LocalPath 'package.json'
    if (-not (Test-Path -LiteralPath $packageJsonPath)) {
        throw "Vendor-Plugin unter '$LocalPath' hat kein package.json."
    }

    $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    $paperclipPlugin = if ($packageJson.ContainsKey('paperclipPlugin')) { $packageJson['paperclipPlugin'] } else { $null }
    $manifestRelativePath = if ($null -ne $paperclipPlugin -and $paperclipPlugin.ContainsKey('manifest')) {
        [string]$paperclipPlugin['manifest']
    } else {
        'manifest.js'
    }

    return @{
        PackageJsonPath = $packageJsonPath
        PackageJson = $packageJson
        ManifestRelativePath = $manifestRelativePath
        ManifestPath = Join-Path $LocalPath $manifestRelativePath
        HasPackageLock = Test-Path -LiteralPath (Join-Path $LocalPath 'package-lock.json')
        HasNodeModules = Test-Path -LiteralPath (Join-Path $LocalPath 'node_modules')
    }
}

function Get-VorceStudiosNpmExecutable {
    $npmCommand = Get-Command 'npm.cmd' -ErrorAction SilentlyContinue
    if ($null -ne $npmCommand) {
        return $npmCommand.Source
    }

    $npmCommand = Get-Command 'npm' -ErrorAction SilentlyContinue
    if ($null -ne $npmCommand) {
        return $npmCommand.Source
    }

    throw 'npm ist nicht verfuegbar.'
}

function Invoke-VorceStudiosVendorBuildCommand {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $npmExecutable = Get-VorceStudiosNpmExecutable
    Push-Location $LocalPath
    try {
        & $npmExecutable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw ("Vendor-Plugin Build fehlgeschlagen: {0} {1}" -f $npmExecutable, ($Arguments -join ' '))
        }
    } finally {
        Pop-Location
    }
}

function Ensure-VorceStudiosGitHubIssuesVendorOverrides {
    param(
        [Parameter(Mandatory)][string]$LocalPath
    )

    Sync-VorceStudiosVendorOverrideFiles -PluginId 'paperclip-plugin-github-issues' -LocalPath $LocalPath | Out-Null
}

function Ensure-VorceStudiosChatVendorOverrides {
    param(
        [Parameter(Mandatory)][string]$LocalPath
    )

    $packageJsonPath = Join-Path $LocalPath 'package.json'
    if (Test-Path -LiteralPath $packageJsonPath) {
        Update-VorceStudiosVendorPackageJson -PackageJsonPath $packageJsonPath -Mutator {
            param([hashtable]$package)

            if (-not $package.ContainsKey('dependencies') -or $null -eq $package.dependencies) {
                $package['dependencies'] = @{}
            }

            $package.dependencies['@paperclipai/plugin-sdk'] = '^2026.403.0'
            $package.dependencies['react-markdown'] = '^10.1.0'
            $package.dependencies['remark-gfm'] = '^4.0.1'
        }
    }

    Sync-VorceStudiosVendorOverrideFiles -PluginId 'paperclip-plugin-chat' -LocalPath $LocalPath | Out-Null
}

function Ensure-VorceStudiosVendorPluginSource {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    $definition = Get-VorceStudiosPluginSourceDefinition -PluginId $PluginId
    if ($null -eq $definition) {
        throw "Plugin-Quelle '$PluginId' ist nicht definiert."
    }

    $localPath = [string]$definition.LocalPath
    if (-not (Test-Path -LiteralPath $localPath)) {
        git clone --depth 1 $definition.Repository $localPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Plugin-Quelle '$PluginId' konnte nicht geklont werden."
        }
    }

    switch ([string]$definition.SourceName) {
        'paperclip-plugin-github-issues' {
            Ensure-VorceStudiosGitHubIssuesVendorOverrides -LocalPath $localPath
        }
        'paperclip-plugin-chat' {
            Ensure-VorceStudiosChatVendorOverrides -LocalPath $localPath
        }
    }

    return $localPath
}

function Ensure-VorceStudiosVendorPluginBuild {
    param(
        [Parameter(Mandatory)][string]$LocalPath
    )

    $manifestInfo = Get-VorceStudiosVendorPackageManifestInfo -LocalPath $LocalPath
    if (-not $manifestInfo.HasNodeModules) {
        Invoke-VorceStudiosVendorBuildCommand -LocalPath $LocalPath -Arguments @('install')
    }

    Invoke-VorceStudiosVendorBuildCommand -LocalPath $LocalPath -Arguments @('run', 'build')
    $manifestInfo = Get-VorceStudiosVendorPackageManifestInfo -LocalPath $LocalPath
    if (-not (Test-Path -LiteralPath $manifestInfo.ManifestPath)) {
        throw "Vendor-Plugin unter '$LocalPath' wurde gebaut, aber das Manifest '$($manifestInfo.ManifestRelativePath)' fehlt weiterhin."
    }

    return $manifestInfo
}

function Get-VorceStudiosPaperclipPluginLoaderPaths {
    $system = Get-VorceStudiosSystemPolicy
    $cacheRoot = Join-Path $env:LOCALAPPDATA 'pnpm-cache\dlx'
    if (-not (Test-Path -LiteralPath $cacheRoot)) {
        return @()
    }

    $pattern = ('@paperclipai+server@{0}' -f $system.Company.PaperclipVersion)
    return @(
        Get-ChildItem -Path $cacheRoot -Recurse -Filter 'plugin-loader.js' -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -like '*\@paperclipai\server\dist\services\plugin-loader.js' -and
                $_.FullName -like ('*{0}*' -f $pattern)
            } |
            Select-Object -ExpandProperty FullName
    )
}

function Ensure-VorceStudiosPaperclipPluginLoaderPatched {
    $paths = Get-VorceStudiosPaths
    $loaderPaths = Get-VorceStudiosPaperclipPluginLoaderPaths
    $patched = New-Object System.Collections.Generic.List[string]

    foreach ($loaderPath in $loaderPaths) {
        $raw = Get-Content -LiteralPath $loaderPath -Raw -ErrorAction Stop
        $updated = $raw

        if ($updated -match 'import \{ fileURLToPath \} from "node:url";') {
            $updated = $updated -replace 'import \{ fileURLToPath \} from "node:url";', 'import { fileURLToPath, pathToFileURL } from "node:url";'
        }

        if ($updated -notmatch 'const npmExecutable = process\.platform === "win32" \? "npm\.cmd" : "npm";') {
            $updated = $updated -replace 'const DEV_TSX_LOADER_PATH = path\.resolve\(__dirname, "\.\./\.\./\.\./cli/node_modules/tsx/dist/loader\.mjs"\);', "`$0`nconst npmExecutable = process.platform === `"win32`" ? `"npm.cmd`" : `"npm`";"
        }

        $updated = $updated -replace 'await execFileAsync\("npm",', 'await execFileAsync(npmExecutable,'
        $updated = $updated -replace 'const mod = await import\(manifestPath\);', 'const mod = await import(pathToFileURL(manifestPath).href);'

        if ($updated -ne $raw) {
            [System.IO.File]::WriteAllText($loaderPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
            $patched.Add($loaderPath) | Out-Null
        }
    }

    Write-VorceStudiosJsonFile -Path $paths.PluginPatchStatePath -Value @{
        patchedAt = Get-VorceStudiosTimestamp
        loaderPaths = $loaderPaths
        changed = $patched.ToArray()
    }

    return $patched.ToArray()
}

function Get-VorceStudiosPluginToolNames {
    $tools = Invoke-VorceStudiosApi -Method GET -Path '/api/plugins/tools' -IgnoreFailure
    if ($null -eq $tools) {
        return @()
    }

    return @($tools | ForEach-Object {
        if ($_ -is [string]) {
            $_
        } elseif ($_.PSObject.Properties.Name -contains 'tool') {
            [string]$_.tool
        } elseif ($_.PSObject.Properties.Name -contains 'name') {
            [string]$_.name
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Resolve-VorceStudiosGitHubLinkToolName {
    $tools = Get-VorceStudiosPluginToolNames
    foreach ($candidate in @('paperclip-plugin-github-issues:link', 'paperclip-plugin-github-issues.link', 'github-issues:link', 'link')) {
        if ($tools -contains $candidate) {
            return $candidate
        }
    }

    return 'link'
}

function Ensure-VorceStudiosCompanySecretByName {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [string]$Description = '',
        [switch]$RotateValue
    )

    $matches = @(
        Get-VorceStudiosCompanySecrets -CompanyId $CompanyId |
            Where-Object { [string]$_.name -eq $Name } |
            Select-Object -First 1
    )
    $existing = if ($matches.Count -gt 0) { $matches[0] } else { $null }

    if ($existing) {
        if ($RotateValue.IsPresent) {
            Rotate-VorceStudiosSecret -SecretId ([string]$existing.id) -Value $Value | Out-Null
            $matches = @(
                Get-VorceStudiosCompanySecrets -CompanyId $CompanyId |
                    Where-Object { [string]$_.name -eq $Name } |
                    Select-Object -First 1
            )
            if ($matches.Count -gt 0) {
                return $matches[0]
            }
        }

        return $existing
    }

    return New-VorceStudiosCompanySecret -CompanyId $CompanyId -Name $Name -Value $Value -Description $Description
}

function Ensure-VorceStudiosPluginInstalledFromVendor {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    $definition = Get-VorceStudiosPluginSourceDefinition -PluginId $PluginId
    if ($null -eq $definition) {
        throw "Plugin-Quelle '$PluginId' ist nicht definiert."
    }

    $localPath = Ensure-VorceStudiosVendorPluginSource -PluginId $PluginId
    Ensure-VorceStudiosVendorPluginBuild -LocalPath $localPath | Out-Null

    $existing = Find-VorceStudiosPlugin -PluginId ([string]$definition.PluginId)
    if ($null -eq $existing -and -not [string]::IsNullOrWhiteSpace([string]$definition.PackageName)) {
        $existing = Find-VorceStudiosPlugin -PluginId ([string]$definition.PackageName)
    }
    if ($existing) {
        return $existing
    }

    $installed = Install-VorceStudiosPlugin -PackageName $localPath -IsLocalPath
    return (Find-VorceStudiosPlugin -PluginId ([string]$definition.PluginId)) ?? (Find-VorceStudiosPlugin -PluginId ([string]$definition.PackageName)) ?? $installed
}

function Ensure-VorceStudiosPluginInstalledFromRegistry {
    param(
        [Parameter(Mandatory)][string]$PackageName,
        [string]$Version
    )

    $existing = Find-VorceStudiosPlugin -PluginId $PackageName
    if ($existing) {
        return $existing
    }

    return Install-VorceStudiosPlugin -PackageName $PackageName -Version $Version
}

function Ensure-VorceStudiosGitHubPlugin {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $plugin = Ensure-VorceStudiosPluginInstalledFromVendor -PluginId 'paperclip-plugin-github-issues'

    $ghToken = (& gh auth token 2>$null | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($ghToken)) {
        throw 'GitHub CLI ist nicht angemeldet.'
    }

    $syncPolicy = Get-VorceStudiosPolicy -Name 'sync'
    $secret = Ensure-VorceStudiosCompanySecretByName -CompanyId $Context.Company.id -Name 'Vorce GitHub PAT' -Value $ghToken -Description 'GitHub token used by paperclip-plugin-github-issues.' -RotateValue

    Set-VorceStudiosPluginConfig -PluginId ([string]$plugin.id) -Config @{
        githubTokenRef = [string]$secret.id
        defaultRepo = [string]$syncPolicy.GitHub.Repository
        syncComments = $true
        syncDirection = 'bidirectional'
    } | Out-Null

    $current = Find-VorceStudiosPlugin -PluginId 'paperclip-plugin-github-issues'
    if ($null -ne $current -and [string]$current.status -ne 'ready') {
        Enable-VorceStudiosPlugin -PluginId ([string]$current.id) | Out-Null
    }

    return Find-VorceStudiosPlugin -PluginId 'paperclip-plugin-github-issues'
}

function Ensure-VorceStudiosChatPlugin {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $plugin = Ensure-VorceStudiosPluginInstalledFromVendor -PluginId 'paperclip-chat'
    if ($null -ne $plugin -and [string]$plugin.status -ne 'ready') {
        Enable-VorceStudiosPlugin -PluginId ([string]$plugin.id) | Out-Null
        return Find-VorceStudiosPlugin -PluginId 'paperclip-chat'
    }

    return $plugin
}

function Ensure-VorceStudiosAperturePlugin {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $plugin = Ensure-VorceStudiosPluginInstalledFromVendor -PluginId 'tomismeta.paperclip-aperture'
    if ($null -ne $plugin -and [string]$plugin.status -ne 'ready') {
        Enable-VorceStudiosPlugin -PluginId ([string]$plugin.id) | Out-Null
        return (Find-VorceStudiosPlugin -PluginId 'tomismeta.paperclip-aperture') ?? (Find-VorceStudiosPlugin -PluginId '@tomismeta/paperclip-aperture')
    }

    return $plugin
}

function Ensure-VorceStudiosLiveAnalyticsPlugin {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $plugin = Ensure-VorceStudiosPluginInstalledFromVendor -PluginId 'agent-analytics.paperclip-live-analytics-plugin'
    if ($null -ne $plugin -and [string]$plugin.status -ne 'ready') {
        Enable-VorceStudiosPlugin -PluginId ([string]$plugin.id) | Out-Null
        return (Find-VorceStudiosPlugin -PluginId 'agent-analytics.paperclip-live-analytics-plugin') ?? (Find-VorceStudiosPlugin -PluginId '@agent-analytics/paperclip-live-analytics-plugin')
    }

    return $plugin
}

function Ensure-VorceStudiosTelegramPlugin {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    return Ensure-VorceStudiosPluginInstalledFromVendor -PluginId 'paperclip-plugin-telegram'
}

function Connect-VorceStudiosGitHubPluginLinks {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    return @{
        mode = 'metadata_backfill'
    }
}

function Invoke-VorceStudiosGitHubPluginPeriodicSync {
    param(
        [switch]$IgnoreFailure
    )

    $plugin = Find-VorceStudiosPlugin -PluginId 'paperclip-plugin-github-issues'
    if ($null -eq $plugin) {
        return $null
    }

    $job = @(
        Get-VorceStudiosPluginJobs -PluginId ([string]$plugin.id) |
            Where-Object { [string]$_.jobKey -eq 'periodic-sync' } |
            Select-Object -First 1
    )[0]

    if ($null -eq $job) {
        return $null
    }

    try {
        return Invoke-VorceStudiosPluginJob -PluginId ([string]$plugin.id) -JobId ([string]$job.id)
    } catch {
        if ($IgnoreFailure.IsPresent) {
            return $null
        }
        throw
    }
}

function Ensure-VorceStudiosPlugins {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    Ensure-VorceStudiosPaperclipPluginLoaderPatched | Out-Null
    $github = Ensure-VorceStudiosGitHubPlugin -Context $Context
    $chat = Ensure-VorceStudiosChatPlugin -Context $Context
    $aperture = Ensure-VorceStudiosAperturePlugin -Context $Context
    $liveAnalytics = Ensure-VorceStudiosLiveAnalyticsPlugin -Context $Context
    Connect-VorceStudiosGitHubPluginLinks -Context $Context | Out-Null

    return @{
        github = $github
        chat = $chat
        aperture = $aperture
        liveAnalytics = $liveAnalytics
    }
}
