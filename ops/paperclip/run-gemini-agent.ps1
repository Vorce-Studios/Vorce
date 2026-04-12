#!/usr/bin/env pwsh
# run-gemini-agent.ps1 - Wrapper for Paperclip process adapter
param(
    [Parameter(Mandatory)][string]$Prompt,
    [string]$InstructionPath,
    [string]$PolicyRoot,
    [string]$RoleKey
)

$env:VORCE_STUDIOS_ROLE = $RoleKey

gemini -y -p $Prompt
