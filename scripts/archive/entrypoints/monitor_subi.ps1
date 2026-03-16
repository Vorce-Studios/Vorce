$ScriptDir = Split-Path -Parent $PSCommandPath
& (Join-Path $ScriptDir 'gemini-cli\monitor-subi.ps1') @args
exit $LASTEXITCODE
