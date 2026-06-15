# TriageUtils.ps1 (Vorce 3.0)
# Hilfsfunktionen zur Filterung und Bewertung von GitHub Issues

function Get-VorceTriagedIssues {
    param(
        [Parameter(Mandatory)][object]$Issues,
        [Parameter(Mandatory)][object]$Config
    )

    Write-VorceStep -Message "Starte Triage für $($Issues.Count) Issues..." -Status "RUN"

    $includeLabels = $Config.issue_filters.include_labels
    $excludeLabels = $Config.issue_filters.exclude_labels

    $triaged = @()

    foreach ($issue in $Issues) {
        $labelNames = @($issue.labels.name)

        # 1. Ausschluss-Filter
        $isExcluded = $false
        foreach ($ex in $excludeLabels) {
            if ($labelNames -contains $ex) {
                $isExcluded = $true
                break
            }
        }
        if ($isExcluded) { continue }

        # 2. Einschluss-Filter
        $isIncluded = $false
        foreach ($inc in $includeLabels) {
            if ($labelNames -contains $inc) {
                $isIncluded = $true
                break
            }
        }

        if ($isIncluded) {
            $triaged += $issue
        }
    }

    Write-VorceStep -Message "$($triaged.Count) Issues nach Filterung verbleibend." -Status "OK"
    return $triaged
}

# Ende TriageUtils
