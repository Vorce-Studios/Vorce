@{
    Skills = @(
        @{
            Id          = 'rust-crate-development'
            Name        = 'Rust Crate Development'
            Description = 'Rust/Cargo Build-System, Crate-Struktur, unsafe Code, FFI-Bindings.'
            AssignedTo  = @('jules', 'antigravity', 'codex')
        }
        @{
            Id          = 'egui-ui-development'
            Name        = 'eGUI/UI Development'
            Description = 'egui Widgets, Custom Rendering, UI-State-Management, Themes.'
            AssignedTo  = @('jules', 'antigravity')
        }
        @{
            Id          = 'cicd-pipeline'
            Name        = 'CI/CD Pipeline Management'
            Description = 'GitHub Actions Workflows, Cross-Platform Builds, Release-Automation.'
            AssignedTo  = @('jules', 'gemini', 'antigravity')
        }
        @{
            Id          = 'code-review'
            Name        = 'Code Review und Quality'
            Description = 'PR-Review, Regression-Check, Code-Style, Test-Coverage-Analyse.'
            AssignedTo  = @('gemini', 'qwen', 'codex')
        }
        @{
            Id          = 'architecture-analysis'
            Name        = 'Architecture Analysis'
            Description = 'Crate-Dependency-Analyse, Performance-Profiling, Design-Patterns.'
            AssignedTo  = @('codex', 'gemini')
        }
        @{
            Id          = 'media-pipeline'
            Name        = 'Media und Render Pipeline'
            Description = 'FFmpeg, WGPU, Video-Decoding, Audio-Backend (CPAL), GPU-Rendering.'
            AssignedTo  = @('codex', 'jules', 'antigravity')
        }
        @{
            Id          = 'documentation'
            Name        = 'Documentation und Release Notes'
            Description = 'Markdown-Docs, API-Docs, CHANGELOG, README-Updates.'
            AssignedTo  = @('gemini', 'antigravity', 'qwen')
        }
        @{
            Id          = 'test-generation'
            Name        = 'Test Generation'
            Description = 'Unit-Tests, Integration-Tests, Benchmark-Tests, Mocking-Strategien.'
            AssignedTo  = @('antigravity', 'jules', 'gemini')
        }
        @{
            Id          = 'swarm-orchestration'
            Name        = 'Multi-Agent Swarm Missions'
            Description = 'antigravity-swarm Planner/Orchestrator fuer parallele Aufgaben.'
            AssignedTo  = @('antigravity')
        }
        @{
            Id          = 'jules-diagnostic'
            Name        = 'Jules Session Diagnostics'
            Description = 'Ueberwachung und Diagnose laufender Session-Blockaden.'
            AssignedTo  = @('qwen')
        }
        @{
            Id          = 'ci-failure-analysis'
            Name        = 'CI/PR Failure Analysis'
            Description = 'Diagnose von failed PR-Checks und Merge-Konflikten.'
            AssignedTo  = @('qwen', 'gemini')
        }
        @{
            Id          = 'issue-planning'
            Name        = 'Issue Planning und Priorisierung'
            Description = 'Backlog-Gestaltung, Sprint-Planung und strategisches Task-Routing.'
            AssignedTo  = @('ceo', 'lena')
        }
        @{
            Id          = 'feature-integration'
            Name        = 'Feature Integration & Architecture'
            Description = 'Systemarchitektur entwerfen und nahtlose Feature-Gruppen zusammenführen.'
            AssignedTo  = @('ceo', 'antigravity')
        }
        @{
            Id          = 'information-broker'
            Name        = 'Information Brokering'
            Description = 'Rohdaten konsolidieren, verfeinern und für Führungskräfte bündeln.'
            AssignedTo  = @('lena', 'chief_of_staff')
        }
        @{
            Id          = 'agile-management'
            Name        = 'Agile Management & Routing'
            Description = 'Lastverteilung (Load Balancing) und Dynamisches Routing im Agent-Swarm.'
            AssignedTo  = @('chief_of_staff')
        }
        @{
            Id          = 'rust-idiomatic-review'
            Name        = 'Idiomatic Rust Code Review'
            Description = 'Memory Safety Verification, Ownership/Lifetimes, Best Practices, Performance.'
            AssignedTo  = @('gemini', 'codex')
        }
        @{
            Id          = 'gpu-compute-architecture'
            Name        = 'GPU Compute & Rendering'
            Description = 'WGPU Pipeline Optimierung, Shader-Design, Render-Graph Structuring.'
            AssignedTo  = @('ceo', 'antigravity')
        }
        @{
            Id          = 'qa-automation-design'
            Name        = 'QA Automation Design'
            Description = 'Automatisierte UI-Tests, eGUI Snapshot-Testing, Mocking Design.'
            AssignedTo  = @('ops', 'qwen', 'jules')
        }
        # --- Neue Skills (gezielt nach Lückenanalyse) ---
        @{
            Id          = 'wgpu-rendering-pipeline'
            Name        = 'WGPU Rendering Pipeline'
            Description = 'GPU-Rendering, WGSL-Shader, Textur-Streaming, Render-Passes, Multi-Adapter Selection.'
            AssignedTo  = @('jules', 'antigravity', 'ceo')
        }
        @{
            Id          = 'cpal-audio-engineering'
            Name        = 'CPAL Audio Engineering'
            Description = 'Echtzeit-Audio, FFT-Analyse (rustfft), Lock-free Channels (crossbeam), Latenz-Tuning.'
            AssignedTo  = @('jules', 'antigravity', 'codex')
        }
        @{
            Id          = 'ffmpeg-video-pipeline'
            Name        = 'FFmpeg Video Pipeline'
            Description = 'Hardware-Decoding (NVDEC/DXVA2), Codec-Negotiation, Zero-Copy Frame Sharing, FFI-Safety.'
            AssignedTo  = @('jules', 'antigravity', 'codex')
        }
        @{
            Id          = 'security-audit'
            Name        = 'Security & Dependency Audit'
            Description = 'cargo-audit, cargo-deny, Unsafe-Code-Review, RUSTSEC-Advisories, FFI-Security-Boundaries.'
            AssignedTo  = @('codex', 'gemini', 'ops')
        }
        @{
            Id          = 'performance-profiling'
            Name        = 'Performance Profiling'
            Description = 'Flamegraph, Samply, Criterion-Benchmarks, GPU-Profiling (wgpu trace), Memory-Profiling (dhat).'
            AssignedTo  = @('codex', 'gemini', 'jules')
        }
        @{
            Id          = 'cross-platform-build'
            Name        = 'Cross-Platform Build System'
            Description = 'cargo-zigbuild, CI-Matrix-Builds, Native-Dependencies (FFmpeg, libmpv), MSVC/GNU-Toolchain.'
            AssignedTo  = @('jules', 'antigravity', 'gemini')
        }
        @{
            Id          = 'async-concurrency'
            Name        = 'Async & Concurrency Patterns'
            Description = 'Tokio-Runtime, Rayon-Work-Stealing, Arc-swap, Send/Sync-Garantien, SPSC-Channels.'
            AssignedTo  = @('ceo', 'codex', 'antigravity')
        }
        @{
            Id          = 'egui-custom-widgets'
            Name        = 'Egui Custom Widget Dev'
            Description = 'Widget-Trait-Implementation, Epaint-Custom-Painting, Node-Editor, High-DPI, egui-wgpu-Integration.'
            AssignedTo  = @('jules', 'antigravity')
        }
        @{
            Id          = 'discovery-scanning'
            Name        = 'Discovery Codebase Scanning'
            Description = 'Hotspot-Analysis, Regression-Detection, Issue-Enrichment mit Callstacks und Reproduktionsschritten.'
            AssignedTo  = @('discovery')
        }
        @{
            Id          = 'pr-triage'
            Name        = 'PR Triage & Analysis'
            Description = 'PR-Status-Analyse, CI-Log-Auswertung, Merge-Konflikt-Erkennung, Retry-Logic für hängende Checks.'
            AssignedTo  = @('pr_monitor', 'qwen')
        }
        @{
            Id          = 'context-mapping'
            Name        = 'Code Context Mapping'
            Description = 'Modul-Verknüpfungen, Dependency-Graph-Pflege, Code-Atlas-Aktualisierung, Modul-Discovery.'
            AssignedTo  = @('atlas', 'discovery')
        }
        @{
            Id          = 'session-diagnostics'
            Name        = 'Session Diagnostics & Recovery'
            Description = 'Timeout-Detection, Deadlock-Resolution, Session-Recovery, Retry-Strategien bei Blockaden.'
            AssignedTo  = @('jules_monitor', 'qwen')
        }
        @{
            Id          = 'merge-governance'
            Name        = 'Merge Governance & Release'
            Description = 'Branch-Protection, Zero-Regression-Policy, Release-Validation, UI-Gate-Erzwingung.'
            AssignedTo  = @('ops', 'gemini')
        }
        @{
            Id          = 'summary-generation'
            Name        = 'Summary & Briefing Generation'
            Description = 'Issue-Zusammenfassung, Status-Reports, Executive-Briefing für CEO und Chief of Staff.'
            AssignedTo  = @('lena', 'chief_of_staff')
        }
        @{
            Id          = 'adr-governance'
            Name        = 'ADR Governance & Validation'
            Description = 'Architecture Decision Records dokumentieren, validieren und mit Code-Implementierung abgleichen.'
            AssignedTo  = @('ceo', 'codex', 'atlas')
        }
        # --- Additional Skills (Agent Developer Guide + skills.sh Recherche) ---
        @{
            Id          = 'git-advanced-workflows'
            Name        = 'Advanced Git Workflows'
            Description = 'Git Bisect (Regression-Isolierung), Worktrees (parallele Entwicklung), Cherry-Pick, Rebase, Reflog-Recovery.'
            AssignedTo  = @('jules', 'ops', 'gemini')
        }
        @{
            Id          = 'log-analysis'
            Name        = 'Log Analysis & Pattern Detection'
            Description = 'Strukturierte Log-Analyse (tracing JSON), Fehlermuster-Erkennung, Frame-Drop-Spitzen, Tracing-Span-Auswertung.'
            AssignedTo  = @('jules_monitor', 'pr_monitor', 'ops', 'qwen')
        }
        @{
            Id          = 'release-automation'
            Name        = 'Release Automation'
            Description = 'Semantische Versionierung, Changelog-Generierung, Tag-Erstellung, Crate-Publish, GitHub-Release-Pipeline.'
            AssignedTo  = @('ops', 'gemini', 'jules')
        }
        @{
            Id          = 'tech-debt-detection'
            Name        = 'Technical Debt Detection'
            Description = 'Code-Smell-Erkennung, Zyklomatische Komplexitaet, Dead-Code, Debt-Heatmaps, Aenderungshaeufigkeit-Korrelation.'
            AssignedTo  = @('discovery', 'codex', 'gemini')
        }
        @{
            Id          = 'communication-relay'
            Name        = 'Communication & Notification Relay'
            Description = 'Telegram-Nachrichtenverarbeitung, Benachrichtigungs-Routing, Status-Updates, /status-Kommandos.'
            AssignedTo  = @('lena', 'pr_monitor', 'ops')
        }
        @{
            Id          = 'escalation-handling'
            Name        = 'Escalation Handling & Recovery'
            Description = 'Automatische Eskalationspfade, Retry-Logik, Fallback-Triggerung, Agent-Konflikt-Eskalation an CEO/Ops.'
            AssignedTo  = @('jules_monitor', 'pr_monitor', 'chief_of_staff')
        }
        @{
            Id          = 'code-navigation'
            Name        = 'Code Navigation & Indexing'
            Description = 'Codebase-Indexierung, Symbol-Suche, Referenz-Tracking, Trait-Definition-Lokalisierung, Struct-Hierarchie-Analyse.'
            AssignedTo  = @('atlas', 'discovery')
        }
        @{
            Id          = 'issue-quality-assessment'
            Name        = 'Issue Quality Assessment'
            Description = 'Ticket-Qualitaetsbewertung, Reproduzierbarkeitspruefung, Acceptance-Criteria-Validierung, Unvollstaendige-Tickets-Erkennung.'
            AssignedTo  = @('discovery', 'lena')
        }
        # --- Paperclip Agent Developer Guide + skills.sh (Trail of Bits, obra, coderabbit) ---
        @{
            Id          = 'property-based-testing'
            Name        = 'Property-Based Testing'
            Description = 'Eigenschaftsbasierte Tests mit proptest, Invarianten-Validierung, Edge-Case-Generierung fuer Mapping-Logik und Render-Pipeline.'
            AssignedTo  = @('jules', 'antigravity', 'gemini')
        }
        @{
            Id          = 'static-analysis'
            Name        = 'Static Code Analysis'
            Description = 'CodeQL, Semgrep, SARIF-Parsing, clippy-Regeln, benutzerdefinierte Lint-Rules fuer VJMapper-spezifische Muster.'
            AssignedTo  = @('codex', 'gemini', 'qwen')
        }
        @{
            Id          = 'rust-footgun-detection'
            Name        = 'Rust Footgun & Sharp Edges'
            Description = 'Error-prone APIs, gefaehrliche Konfigurationen, unwrap()-Missbrauch, typische Rust-Fallstricke im Echtzeit-Kontext.'
            AssignedTo  = @('codex', 'gemini')
        }
        @{
            Id          = 'mutation-testing'
            Name        = 'Mutation Testing'
            Description = 'Test-Qualitaetsmessung durch Mutation-Campaigns (mewt/muton), Coverage-Validierung, schwache Tests identifizieren.'
            AssignedTo  = @('gemini', 'jules')
        }
        @{
            Id          = 'verification-before-completion'
            Name        = 'Verification Before Completion'
            Description = 'Quality-Gate vor Task-Abschluss: Problem tatsächlich geloest? Build erfolgreich? Tests bestanden? Keine halben Fixes.'
            AssignedTo  = @('jules', 'antigravity', 'ops')
        }
        @{
            Id          = 'api-doc-generation'
            Name        = 'API Documentation Generation'
            Description = 'Strukturierte API-Referenzen aus Rust-Source, rustdoc-Integration, Code-Beispiele, Public-Interface-Dokumentation.'
            AssignedTo  = @('gemini', 'atlas')
        }
        @{
            Id          = 'differential-review'
            Name        = 'Differential Security Review'
            Description = 'Sicherheitszentrierte Diff-Reviews mit Git-Historie-Analyse, Side-Channel-Erkennung, FFI-Change-Impact.'
            AssignedTo  = @('codex', 'gemini')
        }
        @{
            Id          = 'subagent-driven-development'
            Name        = 'Subagent-Driven Development'
            Description = 'Zweistufiger Entwicklungsprozess: Spezifikationskonformitaet + Code-Qualitaet. Subagent-Dispatch fuer Crate-Einheiten.'
            AssignedTo  = @('ceo', 'chief_of_staff', 'antigravity')
        }
        @{
            Id          = 'supply-chain-security'
            Name        = 'Supply Chain Security Audit'
            Description = 'Dependency-Gefahrenanalyse, transitive Abhaengigkeiten, Crate-Maintenance-Status, Lizenz-Kompatibilitaet, Typosquatting.'
            AssignedTo  = @('codex', 'ops')
        }
    )
}
