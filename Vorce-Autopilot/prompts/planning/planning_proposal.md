Basierend auf der Analyse (Kontext: $context), schlage maximal $maxIssues neue Issues vor. Fokus auf kleine Standard-Issues für CLI-Agents. Antworte als JSON-Liste.

Harte Regeln:

- Neue Standard-Issues als `*D**-000_Task-Title` mit `issue_type:"default"` vorschlagen; `000` wird zentral ersetzt.
- Neue Master-Issues nur wenn zwingend erforderlich als `M...-000_Task-Title` mit `issue_type:"master"` vorschlagen.
- Sub-Issues nur als `___M-{ParentMasterID}_s{SubIndex}_Task-Title` mit `issue_type:"sub_issue"`, `parent_master_id` und `sub_index` vorschlagen.
- Keine alten `VOR-`, `__VOR-` oder `MF-StIs_` Formate erzeugen.
- Keine Master-/Tracker-Issues als Jules-Coding-Task vorschlagen.
- Keine Jules-Sessions fuer Merge-Konflikte vorschlagen; Konflikte gehen immer an lokale CLI-Agents.
- `agent: "jules"` nur setzen, wenn das Issue einen konkreten Code-/Test-Scope mit Dateien/Modulen und Acceptance Criteria beschreibt.
- Fuer kleine Bugfixes, Skripte, CI, Tests, Konflikte und unklare Koordinationsarbeit lokale CLI-Agents waehlen.
