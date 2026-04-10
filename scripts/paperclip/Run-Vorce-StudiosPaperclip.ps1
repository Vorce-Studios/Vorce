$target = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\ops\paperclip')).Path 'Run-Vorce-StudiosPaperclip.ps1'
& $target
exit $LASTEXITCODE
