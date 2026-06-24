# SUB-RUN-04_Delegation.ps1 (Vorce 3.0)
# Delegates proposals to Jules and creates GitHub issues idempotently.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [hashtable]$ConfigBag,

    [Parameter(Mandatory)]
    [object]$ParentState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:LibDir 'utils/StatusPrinter.ps1')
. (Join-Path $global:LibDir 'engines/QuotaManager.ps1')
. (Join-Path $global:LibDir 'integrations/GitHubClient.ps1')

function Get-VorceDelegationObjectValue {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }
    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }
    return $null
}

function Get-VorceDelegationIdempotencyKey {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [object]$Proposal
    )

    $issueNumber = Get-VorceDelegationObjectValue -InputObject $Proposal -Name 'issueNumber'
    $proposalId = Get-VorceDelegationObjectValue -InputObject $Proposal -Name 'issueId'
    $origin = if (-not [string]::IsNullOrWhiteSpace([string]$issueNumber)) {
        "issue:$issueNumber"
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$proposalId)) {
        "proposal:$proposalId"
    } else {
        throw 'Proposal benoetigt issueNumber oder issueId fuer einen stabilen Idempotency-Key.'
    }

    $canonicalValue = "{0}`n{1}" -f $Repository.Trim().ToLowerInvariant(), $origin
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = [System.BitConverter]::ToString(
            $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalValue))
        ).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    return "delegation:v1:$hash"
}

function Get-VorceNestedDelegationRecords {
    param(
        [AllowNull()]
        [object]$InputObject,

        [int]$Depth = 0
    )

    if ($null -eq $InputObject -or $Depth -gt 6 -or $InputObject -is [string]) {
        return
    }

    foreach ($item in @($InputObject)) {
        if ($null -eq $item) {
            continue
        }

        $delegations = Get-VorceDelegationObjectValue -InputObject $item -Name 'delegations'
        if ($null -ne $delegations) {
            foreach ($delegation in @($delegations)) {
                if ($null -ne $delegation) {
                    Write-Output $delegation
                }
            }
        }

        foreach ($childName in @('results', 'parts', 'result')) {
            $child = Get-VorceDelegationObjectValue -InputObject $item -Name $childName
            if ($null -ne $child) {
                Get-VorceNestedDelegationRecords -InputObject $child -Depth ($Depth + 1)
            }
        }
    }
}

function Find-VorceDelegationRecord {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Records,

        [Parameter(Mandatory)]
        [string]$IdempotencyKey
    )

    $matches = @($Records | Where-Object {
        (Get-VorceDelegationObjectValue -InputObject $_ -Name 'idempotency_key') -eq $IdempotencyKey
    })
    if ($matches.Count -eq 0) {
        return $null
    }

    $withIssue = @($matches | Where-Object {
        -not [string]::IsNullOrWhiteSpace(
            [string](Get-VorceDelegationObjectValue -InputObject $_ -Name 'issueUrl')
        )
    })
    if ($withIssue.Count -gt 0) {
        return $withIssue[0]
    }
    return $matches[0]
}

function Update-VorceDelegationRecords {
    param(
        [AllowEmptyCollection()]
        [object[]]$Records,
        [Parameter(Mandatory)]
        [object]$Record
    )

    $key = Get-VorceDelegationObjectValue -InputObject $Record -Name 'idempotency_key'
    return @($Records | Where-Object {
        (Get-VorceDelegationObjectValue -InputObject $_ -Name 'idempotency_key') -ne $key
    }) + @($Record)
}

function Write-VorceDelegationJournal {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowEmptyCollection()]
        [object[]]$Records
    )

    $successful = @($Records | Where-Object {
        (Get-VorceDelegationObjectValue -InputObject $_ -Name 'status') -in @('success', 'reused')
    }).Count
    $journal = [ordered]@{
        schema_version = 2
        delegations = @($Records)
        timestamp = (Get-Date).ToString('o')
        total = @($Records).Count
        successful = $successful
        failed = @($Records).Count - $successful
    }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $journal | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
    return [pscustomobject]$journal
}

Write-VorceStep -Message 'Starte Delegation...' -Status 'RUN'

$proposalsDir = Join-Path $global:VarDir 'db/proposals'
$proposals = @()
if (Test-Path -LiteralPath $proposalsDir -PathType Container) {
    $proposalFiles = Get-ChildItem -LiteralPath $proposalsDir -Filter 'proposal_*.json' -File |
        Sort-Object Name
    foreach ($file in $proposalFiles) {
        try {
            $proposals += Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        } catch {
            Write-VorceStep -Message "Fehler beim Lesen von $($file.Name): $($_.Exception.Message)" -Status 'ERROR'
        }
    }
}

if ($proposals.Count -eq 0) {
    Write-VorceStep -Message 'Keine Proposals zum Delegieren gefunden.' -Status 'INFO'
    return @{ status = 'no_proposals'; delegations = @(); count = 0 }
}

Write-VorceStep -Message "Found $($proposals.Count) Proposals to delegate" -Status 'INFO'

$repo = [string]$ConfigBag.Config.repository
$taskJournalFile = Join-Path $global:VarDir 'db/task-journal.json'
$journalDelegations = @()
if (Test-Path -LiteralPath $taskJournalFile -PathType Leaf) {
    try {
        $existingJournal = Get-Content -LiteralPath $taskJournalFile -Raw | ConvertFrom-Json
        $journalDelegations = @($existingJournal.delegations | Where-Object { $null -ne $_ })
    } catch {
        Write-VorceStep -Message "Bestehendes Task-Journal ist unlesbar: $($_.Exception.Message)" -Status 'WARN'
    }
}

$resultDelegations = @(Get-VorceNestedDelegationRecords -InputObject $ParentState)
$priorStatePath = Join-Path $global:VarDir (
    'run-states/PART_PART-RUN-01_MR-01_Planning__Delegation__CreateDelegations.json'
)
if (Test-Path -LiteralPath $priorStatePath -PathType Leaf) {
    try {
        $priorState = Get-Content -LiteralPath $priorStatePath -Raw | ConvertFrom-Json
        $resultDelegations += @(Get-VorceNestedDelegationRecords -InputObject $priorState)
    } catch {
        Write-VorceStep -Message "Vorheriges Delegation-Resultat ist unlesbar: $($_.Exception.Message)" -Status 'WARN'
    }
}

$runResultsRoot = Join-Path $global:VarDir 'run-results'
if (Test-Path -LiteralPath $runResultsRoot -PathType Container) {
    $delegationResultDirectories = @(Get-ChildItem -LiteralPath $runResultsRoot -Recurse -Directory |
        Where-Object {
            $_.Name -eq 'PART-RUN-01_MR-01_Planning__Delegation__CreateDelegations'
        })
    foreach ($resultDirectory in $delegationResultDirectories) {
        foreach ($resultFile in Get-ChildItem -LiteralPath $resultDirectory.FullName -Filter '*.json' -File) {
            try {
                $storedResult = Get-Content -LiteralPath $resultFile.FullName -Raw | ConvertFrom-Json
                $resultDelegations += @(Get-VorceNestedDelegationRecords -InputObject $storedResult)
            } catch {
                Write-VorceStep -Message "Delegation-Resultat ist unlesbar: $($resultFile.Name)" -Status 'WARN'
            }
        }
    }
}

$delegations = @()
foreach ($proposal in $proposals) {
    $idempotencyKey = $null
    $commandResult = $null
    $delegation = [ordered]@{
        proposalId = $proposal.issueId
        proposalNumber = $proposal.issueNumber
        title = $proposal.title
        status = 'pending'
        timestamp = (Get-Date).ToString('o')
        delegatedTo = 'jules'
        issueUrl = $null
        issueNumber = $null
        idempotency_key = $null
        side_effect = 'not_started'
        error_class = $null
        errorMessage = $null
    }

    Write-VorceStep -Message "Delegiere Proposal: $($proposal.title)" -Status 'RUN'

    try {
        $idempotencyKey = Get-VorceDelegationIdempotencyKey -Repository $repo -Proposal $proposal
        $delegation.idempotency_key = $idempotencyKey
        $knownRecords = @($journalDelegations) + @($resultDelegations)
        $existing = Find-VorceDelegationRecord -Records $knownRecords -IdempotencyKey $idempotencyKey

        if ($null -ne $existing) {
            $existingUrl = [string](Get-VorceDelegationObjectValue -InputObject $existing -Name 'issueUrl')
            if (-not [string]::IsNullOrWhiteSpace($existingUrl)) {
                $delegation.status = 'reused'
                $delegation.side_effect = 'reused'
                $delegation.issueUrl = $existingUrl
                $delegation.issueNumber = Get-VorceDelegationObjectValue -InputObject $existing -Name 'issueNumber'
                Write-VorceStep -Message "Delegation bereits vorhanden: $existingUrl" -Status 'OK'
            } else {
                $delegation.status = 'blocked'
                $delegation.side_effect = 'suppressed_duplicate'
                $delegation.error_class = 'idempotency_pending'
                $delegation.errorMessage = 'Vorheriger Write-Intent ohne bestaetigtes Resultat; erneuter GitHub-Write wird unterdrueckt.'
                Write-VorceStep -Message $delegation.errorMessage -Status 'WARN'
            }
        } else {
            $quotaOK = $ConfigBag.DryRun -or (Test-VorceQuota -AgentName 'jules')
            if (-not $quotaOK) {
                throw 'Jules Quota erschoepft'
            }

            $title = "Strategy Task: $($proposal.title)"
            $originNumber = if ($proposal.issueNumber) { $proposal.issueNumber } else { $proposal.issueId }
            $deliberationText = if ($proposal.deliberation -is [string]) {
                [string]$proposal.deliberation
            } else {
                $proposal.deliberation | ConvertTo-Json -Depth 5
            }
            $body = @"
Delegiert von Vorce-Factory: Deliberation fuer Issue #$originNumber.

Deliberation Result:
$deliberationText

<!-- vorce-idempotency-key: $idempotencyKey -->
"@

            if ($ConfigBag.DryRun) {
                $delegation.status = 'success'
                $delegation.side_effect = 'dry_run'
                $delegation.issueUrl = "dry-run://delegation/$originNumber"
                $delegation.issueNumber = $originNumber
            } else {
                # Persist the intent before the external side effect. A resume treats
                # an unresolved intent conservatively and never creates a duplicate.
                $intent = [pscustomobject]$delegation
                $intent.status = 'creating'
                $intent.side_effect = 'intent_persisted'
                $journalDelegations = @(Update-VorceDelegationRecords -Records $journalDelegations -Record $intent)
                Write-VorceDelegationJournal -Path $taskJournalFile -Records $journalDelegations | Out-Null

                $commandResult = Invoke-VorceGitHubCommand -Arguments @(
                    'issue', 'create',
                    '--repo', $repo,
                    '--title', $title,
                    '--label', 'jules-task',
                    '--label', 'autopilot-created',
                    '--body', $body
                )
                if (-not $commandResult.Succeeded) {
                    throw "gh issue create fehlgeschlagen: $(Get-VorceGitHubCommandDiagnostic -Result $commandResult)"
                }

                $issueUrl = [string]$commandResult.StdOut
                $issueUrl = $issueUrl.Trim()
                if ($issueUrl -match '(https?://\S+)') {
                    $issueUrl = $Matches[1]
                }
                if ([string]::IsNullOrWhiteSpace($issueUrl)) {
                    throw 'gh issue create lieferte keine Issue-URL.'
                }

                $issueNumber = $null
                if ($issueUrl -match '/issues/(\d+)(?:$|[/?#])') {
                    $issueNumber = [int]$Matches[1]
                }

                $delegation.status = 'success'
                $delegation.side_effect = 'created'
                $delegation.issueUrl = $issueUrl
                $delegation.issueNumber = $issueNumber
                Register-VorceQuotaUsage -AgentName 'jules' -Cost 0 | Out-Null
            }

            Write-VorceStep -Message "GitHub Issue erstellt: $($delegation.issueUrl)" -Status 'OK'
        }
    } catch {
        $delegation.status = 'failed'
        $delegation.side_effect = if ($commandResult -and $commandResult.TimedOut) {
            'outcome_unknown'
        } else {
            'not_confirmed'
        }
        $delegation.error_class = if ($commandResult) { $commandResult.ErrorClass } else { 'delegation_failed' }
        $delegation.errorMessage = $_.Exception.Message
        Write-VorceStep -Message "Fehler bei Delegation: $($_.Exception.Message)" -Status 'ERROR'
    }

    $journalDelegations = @(Update-VorceDelegationRecords -Records $journalDelegations -Record ([pscustomobject]$delegation))
    $delegations += [pscustomobject]$delegation
}

$taskJournal = Write-VorceDelegationJournal -Path $taskJournalFile -Records $journalDelegations

if ($ConfigBag.GlobalState.PSObject.Properties.Name -notcontains 'active_delegations') {
    $ConfigBag.GlobalState | Add-Member -MemberType NoteProperty -Name 'active_delegations' -Value @() -Force
}

foreach ($delegation in $delegations) {
    if ($delegation.status -notin @('success', 'reused')) {
        continue
    }
    $alreadyActive = @($ConfigBag.GlobalState.active_delegations | Where-Object {
        $_.idempotency_key -eq $delegation.idempotency_key -or
        ($null -ne $delegation.issueNumber -and $_.issueNumber -eq $delegation.issueNumber)
    }).Count -gt 0
    if (-not $alreadyActive) {
        $ConfigBag.GlobalState.active_delegations += @{
            issueNumber = $delegation.issueNumber
            title = $delegation.title
            url = $delegation.issueUrl
            timestamp = $delegation.timestamp
            delegatedTo = 'jules'
            idempotency_key = $delegation.idempotency_key
        }
    }
}

$successful = @($delegations | Where-Object { $_.status -in @('success', 'reused') }).Count
$delegationResult = @{
    status = 'completed'
    delegations = $delegations
    count = $delegations.Count
    successful = $successful
    failed = $delegations.Count - $successful
    timestamp = (Get-Date).ToString('o')
}

Write-VorceStep `
    -Message "Delegation abgeschlossen: $($delegationResult.successful) erfolgreich, $($delegationResult.failed) fehlgeschlagen." `
    -Status 'OK'
return $delegationResult
