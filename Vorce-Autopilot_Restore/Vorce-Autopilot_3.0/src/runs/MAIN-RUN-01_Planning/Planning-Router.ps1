# Planning-Router.ps1 (Vorce 3.0)
# Entscheidet, welche Sub-Runs in der Planungsphase ausgeführt werden müssen
[CmdletBinding()]
param(
    [object]$MainState
)

# Vorerst ein hartkodiertes Skelett (Stub)
$RequiredSubRuns = @("SUB-RUN-01_DataSync", "SUB-RUN-02_Triage", "SUB-RUN-03_Strategy")

# Später: Logik zur Prüfung von Quoten, neuen Issues etc.
# if (...) { $RequiredSubRuns += "SUB-RUN-02_Triage" }

return $RequiredSubRuns
