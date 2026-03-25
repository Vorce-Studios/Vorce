$ScriptDir = Split-Path -Parent $PSCommandPath
& (Join-Path $ScriptDir 'gemini-cli\monitor-vorce.ps1') @args
exit $LASTEXITCODE
