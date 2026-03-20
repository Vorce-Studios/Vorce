@echo off
setlocal EnableExtensions

cd /d "%~dp0"

for /f %%B in ('git branch --show-current 2^>nul') do set "ORIG_BRANCH=%%B"
if not defined ORIG_BRANCH (
    echo [ERROR] Konnte den aktuellen Branch nicht ermitteln.
    exit /b 1
)

git show-ref --verify --quiet refs/heads/main
if errorlevel 1 (
    echo [ERROR] Der lokale Branch main existiert nicht.
    exit /b 1
)

set "FILE1=docs\A3_PROJECT\B2_QUALITY\DOC-C5_CODE_AUDIT_REPORT.md"
set "FILE2=crates\mapmap-io\src\stream\encoder.rs"
set "FILE3=crates\mapmap-media\src\decoder.rs"
set "FILE4=crates\mapmap-io\src\ndi\mod.rs"
set "FILE5=crates\mapmap-media\src\hap_player.rs"
set "FILE6=crates\mapmap-control\src\web\handlers.rs"

git diff --quiet HEAD -- "%FILE1%" "%FILE2%" "%FILE3%" "%FILE4%" "%FILE5%" "%FILE6%"
if not errorlevel 1 (
    echo [ERROR] In den Ziel-Dateien wurden keine Aenderungen gegen HEAD gefunden.
    exit /b 1
)

echo [INFO] Aktueller Branch: %ORIG_BRANCH%
echo [INFO] Erstelle Commit nur fuer die Ziel-Dateien...

git commit --only ^
  -m "chore: sync audit report and targeted fixes" ^
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" ^
  -- "%FILE1%" "%FILE2%" "%FILE3%" "%FILE4%" "%FILE5%" "%FILE6%"
if errorlevel 1 (
    echo [ERROR] Commit fehlgeschlagen.
    exit /b 1
)

for /f %%S in ('git rev-parse HEAD 2^>nul') do set "NEW_COMMIT=%%S"
if not defined NEW_COMMIT (
    echo [ERROR] Konnte den neuen Commit nicht ermitteln.
    exit /b 1
)

if /I "%ORIG_BRANCH%"=="main" (
    echo [OK] Commit wurde direkt auf main erstellt: %NEW_COMMIT%
    exit /b 0
)

echo [INFO] Wechsle auf main...
git checkout main
if errorlevel 1 (
    echo [ERROR] Wechsel auf main fehlgeschlagen.
    exit /b 1
)

echo [INFO] Cherry-picke %NEW_COMMIT% nach main...
git cherry-pick "%NEW_COMMIT%"
if errorlevel 1 (
    echo [ERROR] Cherry-pick fehlgeschlagen. Bitte Konflikte loesen und erneut pruefen.
    exit /b 1
)

echo [OK] Die Ziel-Aenderungen wurden nach main uebernommen.
echo [OK] Commit: %NEW_COMMIT%
exit /b 0
