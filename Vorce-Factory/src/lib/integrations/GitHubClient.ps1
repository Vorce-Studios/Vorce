# GitHubClient.ps1 (Vorce 3.0)
# Spezialisierter Client für den Daten-Abruf von GitHub via GH CLI

function Get-VorceGitHubIssues {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [int]$Limit = 100
    )
    
    Write-VorceStep -Message "Lade Issues für $Repository (Limit: $Limit)..." -Status "RUN"

    try {
        $jsonFields = "number,title,labels,assignees,body,state,updatedAt"
        $issuesRaw = gh issue list --repo $Repository --state open --json $jsonFields --limit $Limit 2>&1

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($issuesRaw)) {
            Write-VorceStep -Message "GitHub Issue-Abruf fehlgeschlagen (Code: $LASTEXITCODE): $($issuesRaw | Out-String)" -Status "ERROR"
            return @()
        }

        $issues = $issuesRaw | Out-String | ConvertFrom-Json
        if ($null -eq $issues) {
            Write-VorceStep -Message "GitHub Issues sind null - speichere leeres Array" -Status "WARN"
            return @()
        }
    }
    catch {
        Write-VorceStep -Message "Exception beim Laden Issues: $_" -Status "ERROR"
        return @()
    }
    Write-VorceStep -Message "$($issues.Count) Issues erfolgreich geladen." -Status "OK"
    return @($issues)
}

function Get-VorceGitHubPRs {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [int]$Limit = 50
    )
    
    Write-VorceStep -Message "Lade Pull Requests für $Repository..." -Status "RUN"

    try {
        $jsonFields = "number,title,headRefName,baseRefName,mergeable,statusCheckRollup,isDraft,url,updatedAt"
        $prsRaw = gh pr list --repo $Repository --state open --json $jsonFields --limit $Limit 2>&1

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($prsRaw)) {
            Write-VorceStep -Message "GitHub PR-Abruf fehlgeschlagen (Code: $LASTEXITCODE): $($prsRaw | Out-String)" -Status "ERROR"
            return @()
        }

        $prs = $prsRaw | Out-String | ConvertFrom-Json
        if ($null -eq $prs) {
            Write-VorceStep -Message "GitHub PRs sind null - speichere leeres Array" -Status "WARN"
            return @()
        }
    }
    catch {
        Write-VorceStep -Message "Exception beim Laden PRs: $_" -Status "ERROR"
        return @()
    }
    Write-VorceStep -Message "$($prs.Count) Pull Requests erfolgreich geladen." -Status "OK"
    return @($prs)
}

function Save-VorceGitHubData {
    param(
        [Parameter(Mandatory)][string]$Type, # issues | prs
        [Parameter()][object]$Data
    )

    if ($null -eq $Data) {
        Write-VorceStep -Message "GitHub $Type ist null, speichere leeres Array" -Status "WARN"
        $Data = @()
    }

    $fileName = if ($Type -eq "issues") { "github-issues.json" } else { "pull-requests.json" }
    $dbDir = Join-Path $global:VarDir "db"
    if (-not (Test-Path $dbDir)) { New-Item -ItemType Directory -Path $dbDir -Force | Out-Null }

    $filePath = Join-Path $dbDir $fileName
    $Data | ConvertTo-Json -Depth 10 | Set-Content $filePath -Encoding UTF8
    Write-VorceStep -Message "GitHub $Type in Datenbank gesichert: $fileName (Anzahl: $($Data.Count))" -Status "OK"
}

# Ende GitHubClient
