# NA-14 CLI Safety Audit - PowerShell Scope

Datum: 2026-06-23

## Scope

Dieser Bericht deckt ausschliesslich den zugewiesenen PowerShell-Scope ab:

- `src/lib/integrations/GitHubClient.ps1`
- `src/lib/utils/ProjectManager.ps1`
- `CreateDelegations.ps1`
- `DispatchReviews.ps1`
- `RefillJulesQueue.ps1`
- `test/Test-GitHubCommandSafety.ps1`

`vite.config.ts` und Router-Dateien wurden nicht geaendert. Sie liegen ausserhalb dieses Eigentums.

## Audit-Tabelle

| Datei | Zeile | Klassifikation | Fix / Ergebnis |
|---|---:|---|---|
| `src/lib/integrations/GitHubClient.ps1` | 108 | `must_migrate` | Zentraler `Invoke-VorceGitHubCommand` verwendet `ProcessStartInfo` ohne Shell, nimmt ausschliesslich ein Argumentarray an und liefert `ExitCode`, `StdOut`, `StdErr`, `Timeout`, `TimedOut` und `ErrorClass`. |
| `src/lib/integrations/GitHubClient.ps1` | 148 | `safe_direct_process` | `pwsh` nutzt `ProcessStartInfo.ArgumentList`; Windows PowerShell 5.1 nutzt native Windows-argv-Quotierung fuer `ProcessStartInfo.Arguments`. Es findet keine Shell-Auswertung statt. |
| `src/lib/integrations/GitHubClient.ps1` | 257 | `must_migrate` | Direkter `gh issue list`-Aufruf wurde auf den zentralen Helper mit separaten Argumenten migriert. |
| `src/lib/integrations/GitHubClient.ps1` | 291 | `must_migrate` | Direkter `gh pr list`-Aufruf wurde auf den zentralen Helper mit separaten Argumenten migriert. |
| `src/lib/utils/ProjectManager.ps1` | 26 | `must_migrate` | `Invoke-GhCommand` ist nur noch ein JSON-Kompatibilitaetswrapper um den zentralen Helper. |
| `CreateDelegations.ps1` | 269 | `must_migrate` | Stabiler `idempotency_key` aus normalisiertem Repository und Ursprungs-Issue beziehungsweise Proposal-ID. |
| `CreateDelegations.ps1` | 272 | `must_migrate` | Task-Journal, Parent-/Part-State und persistierte Run-Resultate werden vor dem Write auf denselben Key geprueft. |
| `CreateDelegations.ps1` | 317 | `must_migrate` | Write-Intent wird vor dem externen Side Effect persistiert. Ein unaufgeloester Intent blockiert auf Resume einen zweiten Write. |
| `CreateDelegations.ps1` | 325 | `must_migrate` | `gh issue create` verwendet ein Argumentarray; Repo, Titel, Labels und Body sind getrennte argv-Elemente. |
| `DispatchReviews.ps1` | 35 | `must_migrate` | Direkter GitHub-REST-Pfad wurde durch `gh pr list` ueber den zentralen Helper ersetzt. |
| `RefillJulesQueue.ps1` | 110 | `must_migrate` | Direkter GitHub-REST-Write wurde durch `gh issue create` ueber den zentralen Helper ersetzt. |
| `test/Test-GitHubCommandSafety.ps1` | 126 | `test_fixture` | Repository mit Shell-Metazeichen bleibt ein einzelnes Argument. |
| `test/Test-GitHubCommandSafety.ps1` | 129 | `test_fixture` | Titel mit Quotes, Newline, Semikolon, `&`, `$()` und Backtick bleibt ein einzelnes Argument. |
| `test/Test-GitHubCommandSafety.ps1` | 132 | `test_fixture` | Body mit Quotes, Newline, Semikolon, `&`, `$()` und Backtick bleibt ein einzelnes Argument. |
| `test/Test-GitHubCommandSafety.ps1` | 146 | `test_fixture` | Fehlendes `gh` wird ohne Crash als `command_not_found` gemeldet. |
| `test/Test-GitHubCommandSafety.ps1` | 164 | `test_fixture` | Authfehler behaelt ExitCode/stderr und wird als `auth_failed` klassifiziert. |
| `test/Test-GitHubCommandSafety.ps1` | 182 | `test_fixture` | Timeout beendet den Prozess und liefert `TimedOut=true` sowie `ErrorClass=timeout`. |
| `test/Test-GitHubCommandSafety.ps1` | 323 | `test_fixture` | Ein bestaetigter Task-Journal-Eintrag unterdrueckt einen zweiten Issue-Write. |
| `test/Test-GitHubCommandSafety.ps1` | 348 | `test_fixture` | Ein persistiertes Run-Resultat unterdrueckt den Write auch ohne Task-Journal. |

## Verifikation

Kostenfreie lokale Tests, ohne echte GitHub-Writes:

```text
pwsh -NoProfile -NonInteractive -File Vorce-Factory/test/Test-GitHubCommandSafety.ps1
Ergebnis: 15/15 Checks bestanden

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Vorce-Factory/test/Test-GitHubCommandSafety.ps1
Ergebnis: 15/15 Checks bestanden
```

Die Prozesschecks verwenden den lokalen PowerShell-Host als Fake-CLI. Die
Delegationstests verwenden Stub-Bibliotheken und zaehlen die beabsichtigten
GitHub-Aufrufe, ohne Netzwerkzugriff oder GitHub-Side-Effects.

## Ergebnis

Im zugewiesenen PowerShell-Scope sind keine offenen `must_migrate`-Treffer
vorhanden. Es werden keine GitHub-Kommandos aus Usertext als Shellstring gebaut.
