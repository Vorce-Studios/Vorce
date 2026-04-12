@{
    Skills = @(
        @{
            Id          = 'release-roadmap-sequencing'
            Name        = 'Release Roadmap Sequencing'
            Description = 'Opene Issues in Abhaengigkeiten, Risiko und Release-Hebel ordnen statt stumpf FIFO abzuarbeiten.'
            AssignedTo  = @('ceo')
        }
        @{
            Id          = 'github-issue-triage'
            Name        = 'GitHub Issue Triage'
            Description = 'Issues nach Blockern, Kernpfad, Release-Relevanz und fehlenden Acceptance Criteria klassifizieren.'
            AssignedTo  = @('ceo', 'order_manager')
        }
        @{
            Id          = 'jules-session-orchestration'
            Name        = 'Jules Session Orchestration'
            Description = 'Jules-Sessions starten, Duplikate verhindern, Status lesen, auf PR-Erstellung hinarbeiten und haengende Sessions sauber eskalieren.'
            AssignedTo  = @('order_manager')
        }
        @{
            Id          = 'pr-merge-readiness'
            Name        = 'PR Merge Readiness'
            Description = 'PRs auf Konflikte, Pflicht-Checks, Review-Status und Mergebarkeit pruefen und die exakte naechste Aktion benennen.'
            AssignedTo  = @('order_manager', 'qwen_reviewer', 'codex_reviewer')
        }
        @{
            Id          = 'rust-pr-review'
            Name        = 'Rust PR Review'
            Description = 'Diffs auf Bug-Risiken, Regressionen, fehlende Tests und unsaubere Ownership-/Concurrency-Muster pruefen.'
            AssignedTo  = @('qwen_reviewer', 'codex_reviewer', 'ceo')
        }
        @{
            Id          = 'high-risk-debugging'
            Name        = 'High-Risk Debugging'
            Description = 'Schwierige Architektur-, Rendering-, Persistenz- und Integrationsprobleme tief analysieren und minimal-invasive Fixpfade vorschlagen.'
            AssignedTo  = @('codex_reviewer', 'ceo')
        }
        @{
            Id          = 'verification-evidence'
            Name        = 'Verification Evidence'
            Description = 'Build-, Test-, CLI-, API- und PR-Evidence sammeln, damit nichts als gefixt gilt, bevor der Nachweis da ist.'
            AssignedTo  = @('ceo', 'order_manager', 'qwen_reviewer', 'codex_reviewer')
        }
        @{
            Id          = 'paperclip-control-plane-maintenance'
            Name        = 'Paperclip Control Plane Maintenance'
            Description = 'Adapter, Plugin-Runtime, lokale Config, Port-/DB-Zustand und Heartbeat-Disziplin stabil halten.'
            AssignedTo  = @('ceo', 'order_manager')
        }
        @{
            Id          = 'github-sync-operations'
            Name        = 'GitHub Sync Operations'
            Description = 'Bidirektionalen GitHub-Issue-Sync, Webhook-/Polling-Pfade und Issue-Linking betriebsfaehig halten.'
            AssignedTo  = @('ceo', 'order_manager')
        }
        @{
            Id          = 'telegram-executive-updates'
            Name        = 'Telegram Executive Updates'
            Description = 'Kurze CEO-/Betriebsupdates fuer Telegram bereitstellen und nur relevante Eskalationen nach aussen spiegeln.'
            AssignedTo  = @('ceo', 'order_manager')
        }
        @{
            Id          = 'issue-to-pr-execution'
            Name        = 'Issue to PR Execution'
            Description = 'Aus priorisierten Issues konkrete Implementierungsauftraege mit klaren Akzeptanzkriterien und Merge-Endzustand machen.'
            AssignedTo  = @('ceo', 'order_manager')
        }
        @{
            Id          = 'token-efficient-operation'
            Name        = 'Token Efficient Operation'
            Description = 'Nur notwendige Agenten wecken, keine spekulativen Reviews fahren und Runs frueh als No-Op beenden, wenn nichts Konkretes anliegt.'
            AssignedTo  = @('ceo', 'order_manager', 'qwen_reviewer', 'codex_reviewer')
        }
        @{
            Id          = 'release-gatekeeping'
            Name        = 'Release Gatekeeping'
            Description = 'Vor Merge und Release pruefen, ob die Reihenfolge stimmt: Stabilitaet vor Features, Evidence vor Abschluss, Freigabe vor Versand.'
            AssignedTo  = @('ceo', 'order_manager')
        }
    )
}
