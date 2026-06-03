# scripts/codex-cli/lib/autopilot-prompts.ps1
# Role prompts for the Vorce Autopilot runtime.
# Dynamically loaded from config if available.

Set-StrictMode -Version Latest

function Get-VorceConfigPrompt {
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$PromptKey,
        [hashtable]$Variables = @{}
    )

    $promptTemplate = if ($Config.prompts.PSObject.Properties.Match($PromptKey).Count -gt 0) {
        $Config.prompts.$PromptKey
    } else {
        "Missing prompt template for key: $PromptKey"
    }

    $finalPrompt = $promptTemplate
    foreach ($key in $Variables.Keys) {
        $finalPrompt = $finalPrompt.Replace("`$$key", [string]$Variables[$key])
    }

    return $finalPrompt
}

function Get-VorceDashboardDataInstructions {
    return @"
Pflicht-Lagebild vor jeder Entscheidung:
1. Lies scripts/codex-cli/autopilot-tasks.md.
2. Lies scripts/codex-cli/autopilot-state.json.
3. Lies scripts/codex-cli/dashboard/public/registry.json.
4. Lies scripts/codex-cli/dashboard/public/github-issues.json.
5. Lies scripts/codex-cli/dashboard/public/pull-requests.json.
6. Lies scripts/codex-cli/dashboard/public/active-sessions.json.
7. Nutze diese Daten sichtbar in deiner Entscheidung.
"@.Trim()
}
