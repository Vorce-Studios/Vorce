[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')

function Get-VorceStudiosPnpmDlxRuntimeRoots {
    $dlxRoot = Join-Path $env:LOCALAPPDATA 'pnpm-cache\dlx'
    if (-not (Test-Path -LiteralPath $dlxRoot)) {
        return @()
    }

    $runtimeRoots = New-Object System.Collections.Generic.List[string]
    foreach ($vendorRoot in @(Get-ChildItem -LiteralPath $dlxRoot -Directory -ErrorAction SilentlyContinue)) {
        foreach ($runtimeRoot in @(Get-ChildItem -LiteralPath $vendorRoot.FullName -Directory -ErrorAction SilentlyContinue)) {
            $runtimeRoots.Add($runtimeRoot.FullName)
        }
    }

    return $runtimeRoots.ToArray()
}

function Invoke-VorceStudiosNormalizedPatch {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Find,
        [Parameter(Mandatory)][string]$Replace,
        [Parameter(Mandatory)][string]$Label
    )

    $result = [ordered]@{
        label = $Label
        path = $Path
        status = 'missing'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $newline = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $normalized = $raw -replace "`r`n?", "`n"
    $findNormalized = $Find -replace "`r`n?", "`n"
    $replaceNormalized = $Replace -replace "`r`n?", "`n"

    if ($normalized.Contains($replaceNormalized)) {
        $result.status = 'already'
        return $result
    }

    if (-not $normalized.Contains($findNormalized)) {
        $result.status = 'unmatched'
        return $result
    }

    $patched = $normalized.Replace($findNormalized, $replaceNormalized)
    $final = if ($newline -eq "`n") { $patched } else { $patched -replace "`n", $newline }
    Set-Content -LiteralPath $Path -Value $final -NoNewline
    $result.status = 'patched'
    return $result
}

function Repair-VorceStudiosRuntimeRoot {
    param(
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$PaperclipVersion
    )

    $targets = [ordered]@{
        codexHome = Join-Path $RuntimeRoot ("node_modules\.pnpm\@paperclipai+adapter-codex-local@{0}\node_modules\@paperclipai\adapter-codex-local\dist\server\codex-home.js" -f $PaperclipVersion)
        adapterUtils = Join-Path $RuntimeRoot ("node_modules\.pnpm\@paperclipai+adapter-utils@{0}\node_modules\@paperclipai\adapter-utils\dist\server-utils.js" -f $PaperclipVersion)
        geminiExecute = Join-Path $RuntimeRoot ("node_modules\.pnpm\@paperclipai+adapter-gemini-local@{0}\node_modules\@paperclipai\adapter-gemini-local\dist\server\execute.js" -f $PaperclipVersion)
        geminiTest = Join-Path $RuntimeRoot ("node_modules\.pnpm\@paperclipai+adapter-gemini-local@{0}\node_modules\@paperclipai\adapter-gemini-local\dist\server\test.js" -f $PaperclipVersion)
    }

    $results = New-Object System.Collections.Generic.List[object]

    $codexFind = @'
async function ensureSymlink(target, source) {
    const existing = await fs.lstat(target).catch(() => null);
    if (!existing) {
        await ensureParentDir(target);
        await fs.symlink(source, target);
        return;
    }
    if (!existing.isSymbolicLink()) {
        return;
    }
    const linkedPath = await fs.readlink(target).catch(() => null);
    if (!linkedPath)
        return;
    const resolvedLinkedPath = path.resolve(path.dirname(target), linkedPath);
    if (resolvedLinkedPath === source)
        return;
    await fs.unlink(target);
    await fs.symlink(source, target);
}
'@
    $codexReplace = @'
async function tryCreateSymlink(target, source) {
    await fs.symlink(source, target);
}
async function tryCopySharedFile(target, source, err) {
    const sourceStat = await fs.lstat(source).catch(() => null);
    if (!sourceStat?.isFile()) {
        throw err;
    }
    await fs.copyFile(source, target);
}
async function ensureSymlink(target, source) {
    const existing = await fs.lstat(target).catch(() => null);
    if (!existing) {
        await ensureParentDir(target);
        try {
            await tryCreateSymlink(target, source);
        }
        catch (err) {
            await tryCopySharedFile(target, source, err);
        }
        return;
    }
    if (!existing.isSymbolicLink()) {
        return;
    }
    const linkedPath = await fs.readlink(target).catch(() => null);
    if (!linkedPath)
        return;
    const resolvedLinkedPath = path.resolve(path.dirname(target), linkedPath);
    if (resolvedLinkedPath === source)
        return;
    await fs.unlink(target);
    try {
        await tryCreateSymlink(target, source);
    }
    catch (err) {
        await tryCopySharedFile(target, source, err);
    }
}
'@
    $results.Add((Invoke-VorceStudiosNormalizedPatch -Path $targets.codexHome -Find $codexFind -Replace $codexReplace -Label 'codex-home')) | Out-Null

    $skillLinkFind = @'
export async function ensurePaperclipSkillSymlink(source, target, linkSkill = (linkSource, linkTarget) => fs.symlink(linkSource, linkTarget)) {
'@
    $skillLinkReplace = @'
async function defaultPaperclipSkillLink(linkSource, linkTarget) {
    if (process.platform === "win32") {
        const sourceStat = await fs.lstat(linkSource).catch(() => null);
        if (sourceStat?.isDirectory()) {
            await fs.symlink(path.resolve(linkSource), linkTarget, "junction");
            return;
        }
    }
    await fs.symlink(linkSource, linkTarget);
}
export async function ensurePaperclipSkillSymlink(source, target, linkSkill = defaultPaperclipSkillLink) {
'@
    $results.Add((Invoke-VorceStudiosNormalizedPatch -Path $targets.adapterUtils -Find $skillLinkFind -Replace $skillLinkReplace -Label 'adapter-utils-skill-link')) | Out-Null

    $geminiNotesFind = 'const notes = ["Prompt is passed to Gemini via --prompt for non-interactive execution."];'
    $geminiNotesReplace = 'const notes = ["Prompt is passed to Gemini as a positional prompt for non-interactive execution."];'
    $results.Add((Invoke-VorceStudiosNormalizedPatch -Path $targets.geminiExecute -Find $geminiNotesFind -Replace $geminiNotesReplace -Label 'gemini-execute-notes')) | Out-Null

    $geminiExecuteFind = '        args.push("--prompt", prompt);'
    $geminiExecuteReplace = '        args.push(prompt);'
    $results.Add((Invoke-VorceStudiosNormalizedPatch -Path $targets.geminiExecute -Find $geminiExecuteFind -Replace $geminiExecuteReplace -Label 'gemini-execute-prompt')) | Out-Null

    $geminiTestFind = '            const args = ["--output-format", "stream-json", "--prompt", "Respond with hello."];'
    $geminiTestReplace = '            const args = ["--output-format", "stream-json", "Respond with hello."];'
    $results.Add((Invoke-VorceStudiosNormalizedPatch -Path $targets.geminiTest -Find $geminiTestFind -Replace $geminiTestReplace -Label 'gemini-test-prompt')) | Out-Null

    return $results.ToArray()
}

$paperclipVersion = [string](Get-VorceStudiosSystemPolicy).Company.PaperclipVersion
$patched = New-Object System.Collections.Generic.List[object]
foreach ($runtimeRoot in @(Get-VorceStudiosPnpmDlxRuntimeRoots)) {
    foreach ($result in @(Repair-VorceStudiosRuntimeRoot -RuntimeRoot $runtimeRoot -PaperclipVersion $paperclipVersion)) {
        if ($result.status -eq 'missing') {
            continue
        }

        $resultWithRoot = [ordered]@{
            runtimeRoot = $runtimeRoot
            label = $result.label
            path = $result.path
            status = $result.status
        }
        $patched.Add([pscustomobject]$resultWithRoot)
    }
}

@{
    version = $paperclipVersion
    filesChanged = @($patched | Where-Object { $_.status -eq 'patched' }).Count
    files = $patched.ToArray()
}
