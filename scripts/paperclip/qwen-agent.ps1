<<<<<<< HEAD
# qwen-agent.ps1 - Qwen Agent wrapper for Paperclip process adapter
=======
﻿# qwen-agent.ps1 - Qwen Agent wrapper for Paperclip process adapter
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
# Env vars: VORCE_STUDIOS_ROLE, INSTRUCTION_PATH, POLICY_ROOT
Set-StrictMode -Version Latest

$roleKey = $env:VORCE_STUDIOS_ROLE
$instrPath = $env:INSTRUCTION_PATH
$polRoot = $env:POLICY_ROOT

# Fallback paths if not set
if ([string]::IsNullOrWhiteSpace($polRoot)) {
    $root = Split-Path (Split-Path $PSScriptRoot -Parent)
    $polRoot = Join-Path $root "ops\paperclip\policies"
}

$prompt = @"
You are an AI agent for Vorce-Studios with roleKey='$roleKey'.

Your instructions are at: $instrPath
Your policies are at: $polRoot

**ON STARTUP:** Read both files immediately and execute your role's startup procedure.
Do NOT ask for the paths - they are provided above.
Do NOT ask for permission. Act proactively according to your instructions.
"@

qwen -p "$prompt" --yolo
