# AgentResultValidator.ps1
# Fachliche Output-Validierung und zentrale Fehlerklassifizierung.

function Get-VorceAgentFailurePolicy {
    param([Parameter(Mandatory)][string]$ErrorClass)

    $retryable = $ErrorClass -in @(
        'quota_exhausted'
        'rate_limited'
        'timeout'
        'exit_nonzero'
        'empty_output'
        'invalid_output'
        'invalid_json'
        'schema_mismatch'
        'artifact_missing'
        'unknown_provider_error'
        'chain_exhausted'
    )
    $fallbackRecommended = $ErrorClass -notin @('none')

    return [pscustomobject]@{
        error_class = $ErrorClass
        retryable = $retryable
        fallback_recommended = $fallbackRecommended
    }
}

function Remove-VorceEnclosingCodeFence {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return '' }
    $match = [regex]::Match(
        $Text,
        '\A\s*```(?:json)?[ \t]*\r?\n?(?<payload>.*?)\r?\n?```\s*\z',
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if ($match.Success) {
        return $match.Groups['payload'].Value
    }
    return $Text
}

function Get-VorceObjectPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Test-VorceObjectHasProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function ConvertFrom-VorceProviderWrapper {
    param([Parameter(Mandatory)][string]$Output)

    $candidate = Remove-VorceEnclosingCodeFence -Text $Output
    try {
        $parsed = $candidate | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [pscustomobject]@{
            wrapper_detected = $false
            payload_text = $candidate
            wrapper = $null
        }
    }

    if ($parsed -is [array] -and $parsed.Count -gt 0) {
        $last = $parsed[-1]
        foreach ($name in @('result', 'response', 'output', 'content')) {
            if (Test-VorceObjectHasProperty -Object $last -Name $name) {
                $value = Get-VorceObjectPropertyValue -Object $last -Name $name
                $text = if ($value -is [string]) { $value } else { $value | ConvertTo-Json -Depth 100 -Compress }
                return [pscustomobject]@{
                    wrapper_detected = $true
                    payload_text = $text
                    wrapper = $parsed
                }
            }
        }
    }

    if ($parsed -isnot [array]) {
        $propertyNames = @($parsed.PSObject.Properties.Name)
        $metadataNames = @(
            'type', 'subtype', 'session_id', 'is_error', 'usage', 'cost',
            'duration_ms', 'duration_api_ms', 'model', 'provider'
        )
        foreach ($name in @('result', 'response', 'output', 'content')) {
            if (-not (Test-VorceObjectHasProperty -Object $parsed -Name $name)) { continue }
            $otherNames = @($propertyNames | Where-Object { $_ -ne $name })
            $looksLikeWrapper = $otherNames.Count -eq 0 -or
                @($otherNames | Where-Object { $_ -notin $metadataNames }).Count -eq 0
            if ($looksLikeWrapper) {
                $value = Get-VorceObjectPropertyValue -Object $parsed -Name $name
                $text = if ($value -is [string]) { $value } else { $value | ConvertTo-Json -Depth 100 -Compress }
                return [pscustomobject]@{
                    wrapper_detected = $true
                    payload_text = $text
                    wrapper = $parsed
                }
            }
        }
    }

    return [pscustomobject]@{
        wrapper_detected = $false
        payload_text = $candidate
        wrapper = $null
    }
}

function Get-VorceExpectedOutputSpec {
    param([AllowNull()][object]$ExpectedOutput)

    if ($null -eq $ExpectedOutput) {
        return [pscustomobject]@{ type = 'text'; value = $null; schema = $null }
    }

    if ($ExpectedOutput -is [string]) {
        if ($ExpectedOutput -match '^exact:(.*)$') {
            return [pscustomobject]@{ type = 'exact'; value = $Matches[1]; schema = $null }
        }
        return [pscustomobject]@{
            type = $ExpectedOutput.ToLowerInvariant()
            value = if ($ExpectedOutput -eq 'exact') { 'OK' } else { $null }
            schema = $null
        }
    }

    $type = Get-VorceObjectPropertyValue -Object $ExpectedOutput -Name 'type'
    if (-not $type) { $type = Get-VorceObjectPropertyValue -Object $ExpectedOutput -Name 'format' }
    $value = Get-VorceObjectPropertyValue -Object $ExpectedOutput -Name 'value'
    if ($null -eq $value) { $value = Get-VorceObjectPropertyValue -Object $ExpectedOutput -Name 'exact' }
    $schema = Get-VorceObjectPropertyValue -Object $ExpectedOutput -Name 'schema'

    return [pscustomobject]@{
        type = if ($type) { ([string]$type).ToLowerInvariant() } else { 'text' }
        value = $value
        schema = $schema
    }
}

function Test-VorceJsonType {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$ExpectedType
    )

    switch ($ExpectedType.ToLowerInvariant()) {
        'object' {
            return $null -ne $Value -and
                $Value -isnot [array] -and
                $Value -isnot [string] -and
                $Value -isnot [ValueType]
        }
        'array' { return $Value -is [array] }
        'string' { return $Value -is [string] }
        'integer' {
            return $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or
                $Value -is [int64] -or $Value -is [uint16] -or $Value -is [uint32] -or
                $Value -is [uint64]
        }
        'number' {
            return $Value -is [ValueType] -and
                $Value -isnot [bool] -and
                $Value -isnot [datetime]
        }
        'boolean' { return $Value -is [bool] }
        'null' { return $null -eq $Value }
        default { return $false }
    }
}

function Test-VorceJsonSchemaNode {
    param(
        [AllowNull()][object]$Value,
        [AllowNull()][object]$Schema,
        [string]$Path = '$'
    )

    if ($null -eq $Schema) {
        return [pscustomobject]@{ valid = $true; message = $null }
    }

    $expectedType = Get-VorceObjectPropertyValue -Object $Schema -Name 'type'
    if ($expectedType -and -not (Test-VorceJsonType -Value $Value -ExpectedType ([string]$expectedType))) {
        return [pscustomobject]@{
            valid = $false
            message = "$Path erwartet Typ '$expectedType'."
        }
    }

    $required = @(Get-VorceObjectPropertyValue -Object $Schema -Name 'required')
    foreach ($name in $required) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        if (-not (Test-VorceObjectHasProperty -Object $Value -Name ([string]$name))) {
            return [pscustomobject]@{
                valid = $false
                message = "$Path.$name ist erforderlich."
            }
        }
    }

    $properties = Get-VorceObjectPropertyValue -Object $Schema -Name 'properties'
    if ($properties) {
        $propertyEntries = if ($properties -is [System.Collections.IDictionary]) {
            @($properties.GetEnumerator() | ForEach-Object {
                [pscustomobject]@{ Name = [string]$_.Key; Value = $_.Value }
            })
        } else {
            @($properties.PSObject.Properties)
        }
        foreach ($property in $propertyEntries) {
            if (-not (Test-VorceObjectHasProperty -Object $Value -Name $property.Name)) { continue }
            $child = Test-VorceJsonSchemaNode `
                -Value (Get-VorceObjectPropertyValue -Object $Value -Name $property.Name) `
                -Schema $property.Value `
                -Path "$Path.$($property.Name)"
            if (-not $child.valid) { return $child }
        }
    }

    return [pscustomobject]@{ valid = $true; message = $null }
}

function Get-VorceAgentOutputHash {
    param([Parameter(Mandatory)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-VorceAgentOutputSummary {
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowNull()][object]$Payload
    )

    foreach ($name in @('summary', 'message', 'status', 'outcome')) {
        $value = Get-VorceObjectPropertyValue -Object $Payload -Name $name
        if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Substring(0, [Math]::Min(240, $value.Length))
        }
    }

    $singleLine = ($Text -replace '\s+', ' ').Trim()
    return $singleLine.Substring(0, [Math]::Min(240, $singleLine.Length))
}

function Get-VorceValidNonErrorClass {
    param([AllowNull()][object]$Payload)

    $allowed = @('no_work', 'no_changes', 'no_prs', 'no_delegations', 'insufficient_data')
    foreach ($name in @('status', 'outcome', 'result')) {
        $value = Get-VorceObjectPropertyValue -Object $Payload -Name $name
        if ($value -is [string] -and $allowed -contains $value.ToLowerInvariant()) {
            return $value.ToLowerInvariant()
        }
    }
    return $null
}

function Get-VorceAgentErrorClassification {
    [CmdletBinding()]
    param(
        [int]$ExitCode = 0,
        [AllowNull()][string]$Stdout = '',
        [AllowNull()][string]$Stderr = '',
        [switch]$CommandMissing,
        [switch]$AuthMissing,
        [switch]$QuotaExhausted,
        [switch]$TimedOut,
        [switch]$ArtifactMissing,
        [switch]$UnknownProviderError
    )

    if ($CommandMissing) { return Get-VorceAgentFailurePolicy -ErrorClass 'command_missing' }
    if ($AuthMissing) { return Get-VorceAgentFailurePolicy -ErrorClass 'auth_missing' }
    if ($QuotaExhausted) { return Get-VorceAgentFailurePolicy -ErrorClass 'quota_exhausted' }
    if ($TimedOut) { return Get-VorceAgentFailurePolicy -ErrorClass 'timeout' }
    if ($ArtifactMissing) { return Get-VorceAgentFailurePolicy -ErrorClass 'artifact_missing' }
    if ($UnknownProviderError) { return Get-VorceAgentFailurePolicy -ErrorClass 'unknown_provider_error' }

    $diagnostic = "$Stderr`n$Stdout"
    if ($diagnostic -match '(?i)(unauthorized|authentication failed|not authenticated|invalid api key|login required|missing api key)') {
        return Get-VorceAgentFailurePolicy -ErrorClass 'auth_missing'
    }
    if ($diagnostic -match '(?i)(rate.?limit|too many requests|\b429\b|quota temporarily|resource exhausted)') {
        return Get-VorceAgentFailurePolicy -ErrorClass 'rate_limited'
    }
    if ($diagnostic -match '(?i)(policy blocked|content policy|safety policy|request blocked|permission denied by policy)') {
        return Get-VorceAgentFailurePolicy -ErrorClass 'policy_blocked'
    }
    if ($ExitCode -ne 0) {
        return Get-VorceAgentFailurePolicy -ErrorClass 'exit_nonzero'
    }
    if ([string]::IsNullOrWhiteSpace($Stdout)) {
        return Get-VorceAgentFailurePolicy -ErrorClass 'empty_output'
    }
    return $null
}

function Test-VorceAgentResult {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Stdout,
        [AllowNull()][string]$Stderr = '',
        [AllowNull()][object]$ExpectedOutput = 'text'
    )

    if ([string]::IsNullOrWhiteSpace($Stdout)) {
        $policy = Get-VorceAgentFailurePolicy -ErrorClass 'empty_output'
        return [pscustomobject]@{
            valid = $false
            payload = $null
            normalized_output = ''
            summary = ''
            output_hash = $null
            non_error_class = $null
            wrapper_detected = $false
            error = 'stdout ist leer.'
            error_class = $policy.error_class
            retryable = $policy.retryable
            fallback_recommended = $policy.fallback_recommended
        }
    }

    $spec = Get-VorceExpectedOutputSpec -ExpectedOutput $ExpectedOutput
    $wrapper = ConvertFrom-VorceProviderWrapper -Output $Stdout
    $payloadText = (Remove-VorceEnclosingCodeFence -Text $wrapper.payload_text).Trim()
    $payload = $payloadText
    $validationError = $null
    $errorClass = $null

    switch ($spec.type) {
        'text' {
            $payload = $payloadText
        }
        'exact' {
            $expectedValue = [string]$spec.value
            if ($payloadText -cne $expectedValue) {
                $errorClass = 'schema_mismatch'
                $validationError = "Exact-Output '$expectedValue' wurde nicht geliefert."
            }
        }
        'json' {
            try {
                $payload = $payloadText | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $errorClass = 'invalid_json'
                $validationError = $_.Exception.Message
            }
        }
        'json_schema' {
            try {
                $payload = $payloadText | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $errorClass = 'invalid_json'
                $validationError = $_.Exception.Message
            }
            if (-not $errorClass) {
                $schemaResult = Test-VorceJsonSchemaNode -Value $payload -Schema $spec.schema
                if (-not $schemaResult.valid) {
                    $errorClass = 'schema_mismatch'
                    $validationError = $schemaResult.message
                }
            }
        }
        default {
            $errorClass = 'schema_mismatch'
            $validationError = "Unbekanntes ExpectedOutput-Format '$($spec.type)'."
        }
    }

    if ($errorClass) {
        $policy = Get-VorceAgentFailurePolicy -ErrorClass $errorClass
        return [pscustomobject]@{
            valid = $false
            payload = $null
            normalized_output = $payloadText
            summary = ''
            output_hash = Get-VorceAgentOutputHash -Text $payloadText
            non_error_class = $null
            wrapper_detected = $wrapper.wrapper_detected
            error = $validationError
            error_class = $policy.error_class
            retryable = $policy.retryable
            fallback_recommended = $policy.fallback_recommended
        }
    }

    $nonErrorClass = Get-VorceValidNonErrorClass -Payload $payload
    return [pscustomobject]@{
        valid = $true
        payload = $payload
        normalized_output = $payloadText
        summary = Get-VorceAgentOutputSummary -Text $payloadText -Payload $payload
        output_hash = Get-VorceAgentOutputHash -Text $payloadText
        non_error_class = $nonErrorClass
        wrapper_detected = $wrapper.wrapper_detected
        error = $null
        error_class = $null
        retryable = $false
        fallback_recommended = $false
    }
}
