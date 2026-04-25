Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\..') 'jules\jules-github.ps1')

function Get-VorceStudiosPluginSourceDefinitions {
    $paths = Get-VorceStudiosPaths

    return @(
        @{
            PluginId = 'paperclip-plugin-github-issues'
            Repository = 'https://github.com/mvanhorn/paperclip-plugin-github-issues.git'
            LocalPath = Join-Path $paths.PluginSourcesDir 'paperclip-plugin-github-issues'
        }
        @{
            PluginId = 'paperclip-plugin-telegram'
            Repository = 'https://github.com/mvanhorn/paperclip-plugin-telegram.git'
            LocalPath = Join-Path $paths.PluginSourcesDir 'paperclip-plugin-telegram'
        }
    )
}

function Get-VorceStudiosPluginSourceDefinition {
    param(
        [string]$PluginId
    )

    return @(
        Get-VorceStudiosPluginSourceDefinitions |
            Where-Object { [string]$_.PluginId -eq $PluginId } |
            Select-Object -First 1
    )[0]
}

function Set-VorceStudiosVendorFileContent {
    param(
        [string]$Path,
        [string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Ensure-VorceStudiosGitHubIssuesVendorOverrides {
    param(
        [string]$LocalPath
    )

    $srcSyncPath = Join-Path $LocalPath 'src\sync.ts'
    if (Test-Path -LiteralPath $srcSyncPath) {
        $raw = Get-Content -LiteralPath $srcSyncPath -Raw -ErrorAction Stop
        $updated = $raw

        $updated = $updated.Replace(@"
  await ctx.state.set({
    scopeKind: ""instance"",
    scopeId: ""default"",
    stateKey: linkStateKey(params.paperclipIssueId),
    value: JSON.stringify(link),
  });
"@, @"
  await ctx.state.set({
    scopeKind: ""instance"",
    scopeId: ""default"",
    stateKey: linkStateKey(params.paperclipIssueId),
  }, JSON.stringify(link));
"@)

        $updated = $updated.Replace(@"
  await ctx.state.set({
    scopeKind: ""instance"",
    scopeId: ""default"",
    stateKey: ghStateKey(params.ghOwner, params.ghRepo, params.ghNumber),
    value: params.paperclipIssueId,
  });
"@, @"
  await ctx.state.set({
    scopeKind: ""instance"",
    scopeId: ""default"",
    stateKey: ghStateKey(params.ghOwner, params.ghRepo, params.ghNumber),
  }, params.paperclipIssueId);
"@)

        $updated = $updated.Replace(@"
  await ctx.state.set({
    scopeKind: ""instance"",
    scopeId: ""default"",
    stateKey: linkStateKey(link.paperclipIssueId),
    value: JSON.stringify(link),
  });
"@, @"
  await ctx.state.set({
    scopeKind: ""instance"",
    scopeId: ""default"",
    stateKey: linkStateKey(link.paperclipIssueId),
  }, JSON.stringify(link));
"@)

        if ($updated -ne $raw) {
            Set-VorceStudiosVendorFileContent -Path $srcSyncPath -Content $updated
        }
    }

    $distSyncPath = Join-Path $LocalPath 'dist\sync.js'
    if (Test-Path -LiteralPath $distSyncPath) {
        $raw = Get-Content -LiteralPath $distSyncPath -Raw -ErrorAction Stop
        $updated = $raw

        $updated = $updated.Replace(@"
    await ctx.state.set({
        scopeKind: ""instance"",
        scopeId: ""default"",
        stateKey: linkStateKey(params.paperclipIssueId),
        value: JSON.stringify(link),
    });
"@, @"
    await ctx.state.set({
        scopeKind: ""instance"",
        scopeId: ""default"",
        stateKey: linkStateKey(params.paperclipIssueId),
    }, JSON.stringify(link));
"@)

        $updated = $updated.Replace(@"
    await ctx.state.set({
        scopeKind: ""instance"",
        scopeId: ""default"",
        stateKey: ghStateKey(params.ghOwner, params.ghRepo, params.ghNumber),
        value: params.paperclipIssueId,
    });
"@, @"
    await ctx.state.set({
        scopeKind: ""instance"",
        scopeId: ""default"",
        stateKey: ghStateKey(params.ghOwner, params.ghRepo, params.ghNumber),
    }, params.paperclipIssueId);
"@)

        $updated = $updated.Replace(@"
    await ctx.state.set({
        scopeKind: ""instance"",
        scopeId: ""default"",
        stateKey: linkStateKey(link.paperclipIssueId),
        value: JSON.stringify(link),
    });
"@, @"
    await ctx.state.set({
        scopeKind: ""instance"",
        scopeId: ""default"",
        stateKey: linkStateKey(link.paperclipIssueId),
    }, JSON.stringify(link));
"@)

        if ($updated -ne $raw) {
            Set-VorceStudiosVendorFileContent -Path $distSyncPath -Content $updated
        }
    }
}

function Ensure-VorceStudiosVendorPluginSource {
    param(
        [string]$PluginId
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

    if ([string]$PluginId -eq 'paperclip-plugin-github-issues') {
        foreach ($manifestPath in @(
            (Join-Path $localPath 'dist\manifest.js'),
            (Join-Path $localPath 'src\manifest.ts')
        )) {
            if (-not (Test-Path -LiteralPath $manifestPath)) {
                continue
            }

            $raw = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
            if ($raw -match '"jobs\.schedule"' -or $raw -match "'jobs\.schedule'") {
                continue
            }

            $updated = $raw -replace '"agent\.tools\.register",', '"agent.tools.register",' + [Environment]::NewLine + '        "jobs.schedule",'
            $updated = $updated -replace "'agent\.tools\.register',", "'agent.tools.register'," + [Environment]::NewLine + "        'jobs.schedule',"
            if ($updated -ne $raw) {
                Set-VorceStudiosVendorFileContent -Path $manifestPath -Content $updated
            }
        }

        Ensure-VorceStudiosGitHubIssuesVendorOverrides -LocalPath $localPath
    }

    return $localPath
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
            $patched.Add($loaderPath)
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
        [string]$CompanyId,
        [string]$Name,
        [string]$Value,
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

function Refresh-VorceStudiosVendorPlugin {
    param(
        [string]$PluginId,
        [string]$LocalPath,
        [object]$InstalledPlugin,
        [string[]]$Reasons = @()
    )

    Write-Host ("Refreshing vendor plugin {0}" -f $PluginId)
    Uninstall-VorceStudiosPlugin -PluginId ([string]$InstalledPlugin.id) | Out-Null
    Start-Sleep -Milliseconds 250

    $reinstalled = Install-VorceStudiosPlugin -PackageName $LocalPath -IsLocalPath
    return $reinstalled
}

function Ensure-VorceStudiosPluginInstalledFromVendor {
    param(
        [string]$PluginId
    )

    $localPath = Ensure-VorceStudiosVendorPluginSource -PluginId $PluginId
    $existing = Find-VorceStudiosPlugin -PluginId $PluginId
    if ($existing) {
        return $existing
    }

    return Install-VorceStudiosPlugin -PackageName $localPath -IsLocalPath
}

function Ensure-VorceStudiosGitHubPlugin {
    param(
        [hashtable]$Context
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
        Enable-VorceStudiosPlugin -PluginId ([string]$plugin.id) | Out-Null
    }

    return Find-VorceStudiosPlugin -PluginId 'paperclip-plugin-github-issues'
}

function Ensure-VorceStudiosTelegramPlugin {
    param(
        [hashtable]$Context
    )

    $plugin = Ensure-VorceStudiosPluginInstalledFromVendor -PluginId 'paperclip-plugin-telegram'
    return $plugin
}

function Connect-VorceStudiosGitHubPluginLinks {
    param(
        [hashtable]$Context
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
    if ($null -eq $plugin) { return $null }

    $job = @(
        Get-VorceStudiosPluginJobs -PluginId ([string]$plugin.id) |
            Where-Object { [string]$_.jobKey -eq 'periodic-sync' } |
            Select-Object -First 1
    )[0]

    if ($null -eq $job) { return $null }

    try {
        return Invoke-VorceStudiosPluginJob -PluginId ([string]$plugin.id) -JobId ([string]$job.id)
    } catch {
        return $null
    }
}

function Ensure-VorceStudiosPlugins {
    param(
        [hashtable]$Context
    )

    Ensure-VorceStudiosPaperclipPluginLoaderPatched | Out-Null
    $github = Ensure-VorceStudiosGitHubPlugin -Context $Context
    $telegram = Ensure-VorceStudiosTelegramPlugin -Context $Context
    Connect-VorceStudiosGitHubPluginLinks -Context $Context

    return @{
        github = $github
        telegram = $telegram
    }
}
