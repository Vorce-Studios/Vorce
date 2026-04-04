Set-StrictMode -Version Latest

$script:VorceStudiosMetaBegin = '<!-- vorce-studios-meta:begin -->'
$script:VorceStudiosMetaEnd = '<!-- vorce-studios-meta:end -->'

function Get-VorceStudiosIssueMetadata {
    param(
        [AllowNull()][string]$Text
    )

    $metadata = @{}
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $metadata
    }

    $pattern = [regex]::Escape($script:VorceStudiosMetaBegin) + '(?<body>.*?)' + [regex]::Escape($script:VorceStudiosMetaEnd)
    $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
        return $metadata
    }

    $body = $match.Groups['body'].Value
    foreach ($line in ($body -split '\r?\n')) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -notmatch '^(?<key>[A-Za-z0-9_]+)=(?<value>.*)$') { continue }

        $key = $Matches['key']
        $value = $Matches['value'].Trim()
        if ($value -match ',') {
            $metadata[$key] = @($value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } else {
            $metadata[$key] = $value
        }
    }

    return $metadata
}

function ConvertTo-VorceStudiosMetadataBlock {
    param(
        [Parameter(Mandatory)][hashtable]$Metadata
    )

    $lines = @($script:VorceStudiosMetaBegin)
    foreach ($key in ($Metadata.Keys | Sort-Object)) {
        $value = $Metadata[$key]
        if ($null -eq $value) {
            $renderedValue = ''
        } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            $renderedValue = (@($value) -join ',')
        } else {
            $renderedValue = [string]$value
        }

        $lines += ('{0}={1}' -f $key, $renderedValue)
    }
    $lines += $script:VorceStudiosMetaEnd
    return ($lines -join "`n")
}

function Remove-VorceStudiosMetadataBlock {
    param(
        [AllowNull()][string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $pattern = [regex]::Escape($script:VorceStudiosMetaBegin) + '.*?' + [regex]::Escape($script:VorceStudiosMetaEnd)
    $cleaned = [regex]::Replace($Text, "(?:\s*)$pattern(?:\s*)", '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    return $cleaned.Trim()
}

function Set-VorceStudiosIssueMetadata {
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory)][hashtable]$Metadata
    )

    $cleanBody = Remove-VorceStudiosMetadataBlock -Text $Text
    $block = ConvertTo-VorceStudiosMetadataBlock -Metadata $Metadata

    if ([string]::IsNullOrWhiteSpace($cleanBody)) {
        return $block
    }

    return ("{0}`n`n{1}" -f $cleanBody, $block)
}

function Merge-VorceStudiosIssueMetadata {
    param(
        [AllowNull()][hashtable]$Base,
        [AllowNull()][hashtable]$Update
    )

    $merged = @{}
    foreach ($source in @($Base, $Update)) {
        if ($null -eq $source) { continue }
        foreach ($key in $source.Keys) {
            $merged[$key] = $source[$key]
        }
    }
    return $merged
}
