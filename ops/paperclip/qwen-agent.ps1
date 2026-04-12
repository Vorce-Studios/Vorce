# qwen-agent.ps1 - Qwen Agent wrapper for Paperclip process adapter
# Env vars: VORCE_STUDIOS_ROLE, INSTRUCTION_PATH, POLICY_ROOT
$roleKey = $env:VORCE_STUDIOS_ROLE
$instrPath = $env:INSTRUCTION_PATH
$polRoot = $env:POLICY_ROOT

$prompt = "You are an AI agent for Vorce-Studios with roleKey=$roleKey. Your instructions are at $instrPath. Your policies are at $polRoot. Read both files carefully and follow them."

qwen -y -p $prompt
