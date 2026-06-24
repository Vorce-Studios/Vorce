[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $projectRoot 'src/lib/integrations/AgentResultValidator.ps1')

$test = New-VorceTestContext -Name 'AgentResultValidation'

Write-VorceTestResult -Context $test -Message 'text akzeptiert nicht-leeren stdout' -Passed $(
    (Test-VorceAgentResult -Stdout 'plain text' -ExpectedOutput 'text').valid
)
Write-VorceTestResult -Context $test -Message 'exact akzeptiert exakt OK' -Passed $(
    (Test-VorceAgentResult -Stdout 'OK' -ExpectedOutput @{ type = 'exact'; value = 'OK' }).valid
)
Write-VorceTestResult -Context $test -Message 'exact lehnt abweichenden Output ab' -Passed $(
    (Test-VorceAgentResult -Stdout 'ok' -ExpectedOutput 'exact').error_class -eq 'schema_mismatch'
)

$fencedJson = @'
```json
{"status":"no_work"}
```
'@
$fenced = Test-VorceAgentResult -Stdout $fencedJson -ExpectedOutput 'json'
Write-VorceTestResult -Context $test -Message 'JSON in umschliessender Codefence wird geparst' -Passed $(
    $fenced.valid -and $fenced.payload.status -eq 'no_work'
)
Write-VorceTestResult -Context $test -Message 'Gueltiges no_work ist kein Fehler und empfiehlt keinen Fallback' -Passed $(
    $fenced.non_error_class -eq 'no_work' -and -not $fenced.fallback_recommended
)

$schema = @{
    type = 'object'
    required = @('status', 'count')
    properties = @{
        status = @{ type = 'string' }
        count = @{ type = 'integer' }
    }
}
$validSchema = Test-VorceAgentResult `
    -Stdout '{"status":"ok","count":2}' `
    -ExpectedOutput @{ type = 'json_schema'; schema = $schema }
$missingField = Test-VorceAgentResult `
    -Stdout '{"status":"ok"}' `
    -ExpectedOutput @{ type = 'json_schema'; schema = $schema }
$wrongType = Test-VorceAgentResult `
    -Stdout '{"status":"ok","count":"2"}' `
    -ExpectedOutput @{ type = 'json_schema'; schema = $schema }
Write-VorceTestResult -Context $test -Message 'json_schema prueft Pflichtfelder und Typen' -Passed $(
    $validSchema.valid -and
    $missingField.error_class -eq 'schema_mismatch' -and
    $wrongType.error_class -eq 'schema_mismatch'
)

$wrapper = Test-VorceAgentResult `
    -Stdout '{"type":"result","result":"{\"status\":\"no_changes\"}","usage":{"tokens":1}}' `
    -ExpectedOutput 'json'
Write-VorceTestResult -Context $test -Message 'Provider-Wrapper wird vom fachlichen Payload getrennt' -Passed $(
    $wrapper.valid -and
    $wrapper.wrapper_detected -and
    $wrapper.payload.status -eq 'no_changes' -and
    $wrapper.non_error_class -eq 'no_changes'
)

$invalidJson = Test-VorceAgentResult -Stdout '{"broken":' -ExpectedOutput 'json'
Write-VorceTestResult -Context $test -Message 'Invalides JSON wird nicht repariert' -Passed $(
    -not $invalidJson.valid -and $invalidJson.error_class -eq 'invalid_json'
)

$classificationFixtures = @(
    @{ Name = 'command_missing'; Result = Get-VorceAgentErrorClassification -CommandMissing }
    @{ Name = 'auth_missing'; Result = Get-VorceAgentErrorClassification -ExitCode 1 -Stderr 'Authentication failed' }
    @{ Name = 'quota_exhausted'; Result = Get-VorceAgentErrorClassification -QuotaExhausted }
    @{ Name = 'rate_limited'; Result = Get-VorceAgentErrorClassification -ExitCode 1 -Stderr 'HTTP 429 too many requests' }
    @{ Name = 'timeout'; Result = Get-VorceAgentErrorClassification -TimedOut }
    @{ Name = 'exit_nonzero'; Result = Get-VorceAgentErrorClassification -ExitCode 7 -Stderr 'generic failure' }
    @{ Name = 'empty_output'; Result = Get-VorceAgentErrorClassification -ExitCode 0 -Stdout '' }
    @{ Name = 'policy_blocked'; Result = Get-VorceAgentErrorClassification -ExitCode 1 -Stderr 'content policy blocked request' }
    @{ Name = 'artifact_missing'; Result = Get-VorceAgentErrorClassification -ArtifactMissing }
    @{ Name = 'unknown_provider_error'; Result = Get-VorceAgentErrorClassification -UnknownProviderError }
    @{ Name = 'invalid_json'; Result = $invalidJson }
    @{ Name = 'schema_mismatch'; Result = $missingField }
)
foreach ($fixture in $classificationFixtures) {
    Write-VorceTestResult `
        -Context $test `
        -Message "Fehlerklasse wird klassifiziert: $($fixture.Name)" `
        -Passed ($fixture.Result.error_class -eq $fixture.Name)
}

foreach ($nonError in @('no_work', 'no_changes', 'no_prs', 'no_delegations', 'insufficient_data')) {
    $result = Test-VorceAgentResult -Stdout ('{"status":"' + $nonError + '"}') -ExpectedOutput 'json'
    Write-VorceTestResult `
        -Context $test `
        -Message "Fachlicher Nicht-Fehler bleibt erfolgreich: $nonError" `
        -Passed ($result.valid -and $result.non_error_class -eq $nonError -and -not $result.fallback_recommended)
}

Write-VorceTestResult -Context $test -Message 'Erfolg liefert Summary und SHA-256 statt unklassifiziertem Rohstate' -Passed $(
    $validSchema.summary -and $validSchema.output_hash -match '^[0-9a-f]{64}$'
)

Complete-VorceTest -Context $test
