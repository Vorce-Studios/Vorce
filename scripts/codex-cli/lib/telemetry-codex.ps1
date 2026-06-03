function Get-CodexTelemetryUsage {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ReportDate
    )

    $usage = New-TelemetryUsage
    $usage.source = "codex-local-jsonl"
    $root = Join-Path $HOME ".codex\sessions"
    $dirs = Get-TelemetrySessionDirectories -Root $root -Now (Get-Date)

    foreach ($dir in $dirs) {
        foreach ($file in @(Get-ChildItem -Path $dir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue)) {
            $currentModel = "codex"
            $lineNumber = 0
            foreach ($line in (Read-TelemetryJsonlLines -Path $file.FullName)) {
                $lineNumber++
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                $eventType = [string](Get-TelemetryPropertyValue -Object $event -Name "type")
                $payload = Get-TelemetryPropertyValue -Object $event -Name "payload"
                $payloadType = [string](Get-TelemetryPropertyValue -Object $payload -Name "type")

                if ($eventType -eq "session_meta") {
                    foreach ($field in @("model", "model_slug", "modelProvider", "model_provider")) {
                        $modelCandidate = [string](Get-TelemetryPropertyValue -Object $payload -Name $field)
                        if (-not [string]::IsNullOrWhiteSpace($modelCandidate) -and $modelCandidate -ne "openai") {
                            $currentModel = $modelCandidate
                            break
                        }
                    }
                    continue
                }

                if ($payloadType -eq "task_started") {
                    foreach ($field in @("model", "model_slug")) {
                        $modelCandidate = [string](Get-TelemetryPropertyValue -Object $payload -Name $field)
                        if (-not [string]::IsNullOrWhiteSpace($modelCandidate)) {
                            $currentModel = $modelCandidate
                            break
                        }
                    }
                    continue
                }

                if ($payloadType -ne "token_count" -and $eventType -ne "token_count") { continue }
                if (-not (Test-TelemetryTimestampMatchesDateLocalOrUtc -Timestamp (Get-TelemetryPropertyValue -Object $event -Name "timestamp") -Date $ReportDate)) {
                    continue
                }

                $tokenEvent = if ($payloadType -eq "token_count") { $payload } else { $event }
                $info = Get-TelemetryPropertyValue -Object $tokenEvent -Name "info"
                $tokenUsage = Get-TelemetryPropertyValue -Object $info -Name "last_token_usage"
                if ($null -eq $tokenUsage) {
                    $tokenUsage = Get-TelemetryPropertyValue -Object $info -Name "total_token_usage"
                }
                if ($null -eq $tokenUsage) { continue }

                $modelName = $currentModel
                $cost = Get-ModelCostPerCall -Registry $Registry -ProviderName "codex_orchestrator" -ModelName $modelName
                Add-TelemetryUsage -Usage $usage -ModelName $modelName -Calls 1 `
                    -InputTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokenUsage -Name "input_tokens")) `
                    -OutputTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokenUsage -Name "output_tokens")) `
                    -CachedTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokenUsage -Name "cached_input_tokens")) `
                    -ReasoningTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokenUsage -Name "reasoning_output_tokens")) `
                    -CostUsd $cost

                $rateLimits = Get-TelemetryPropertyValue -Object $tokenEvent -Name "rate_limits"
                if ($null -ne $rateLimits) {
                    $usage | Add-Member -MemberType NoteProperty -Name "rate_limits" -Value $rateLimits -Force
                }
            }
        }
    }

    return $usage
}
