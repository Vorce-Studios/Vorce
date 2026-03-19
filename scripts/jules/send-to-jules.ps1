$ScriptDir = Split-Path -Parent $PSCommandPath
& (Join-Path $ScriptDir 'create-jules-session.ps1') @args
exit $LASTEXITCODE
