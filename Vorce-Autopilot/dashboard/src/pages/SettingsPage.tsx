import { useState, useEffect } from 'react';
import { Save, Loader2, Shield, ListFilter, Cpu, Layers, Settings, Check, AlertCircle, Users, Zap } from 'lucide-react';
import type { AutopilotConfig, QuotaRegistry, MemoryStore } from '../types';
import MemoryPanel from './MemoryPanel';

interface Props {
  config: AutopilotConfig;
  registry: QuotaRegistry;
  memoryStore: MemoryStore;
  onSave: () => void;
  onMemoryRefresh: () => void;
}

const PROVIDER_LABELS: Record<string, string> = {
  jules: 'Jules',
  gemini_cli: 'Gemini CLI',
  kiro_cli: 'Kiro CLI',
  cline_cli: 'Cline CLI',
  claude_code: 'Claude Code',
  copilot_cli: 'Copilot CLI',
  cursor_agent: 'Cursor Agent',
  codex_orchestrator: 'Codex Orchestrator',
};

const ROUTING_DESCRIPTIONS: Record<string, string> = {
  monitoring: 'Überwachung laufender Jules-Sessions, CI-Status und Merge-Konflikten in offenen PRs.',
  simple_review: 'Schneller Check von einfachen Code-Änderungen auf grundlegende Syntax oder Syntaxfehler.',
  code_review: 'Detailliertes Review bezüglich Rust-Konventionen, Code-Qualität und potenziellen Regressionen.',
  complex_review: 'Tiefgehende Prüfung kritischer Architekturänderungen und sicherheitsrelevanter Code-Stellen.',
  planning: 'Repository-Scan und automatische Erstellung passender Issues für neue Autopilot-Aufgaben.',
  analysis: 'Identifikation von Optimierungs- und Refactoring-Potenzialen in Crates und Modulen.',
  qa_disposition: 'Strategische Entscheidung zur Freigabe oder Rückweisung fertiggestellter Tasks.',
  documentation: 'Automatische Erstellung und Aktualisierung von Readmes, Markdown-Dokumenten und Systembeschreibungen.',
  merge_conflict_resolution: 'Automatisches Auflösen und Zusammenführen kollidierender Pull Requests.',
  debugging: 'Kontextbezogene Fehleranalyse und direkter Reparatur-Versuch bei fehlgeschlagenen CI-Builds.',
  coding: 'Der eigentliche Entwicklungs-Prozess von Code-Änderungen und Features (standardmäßig Jules).',
};

const PROMPT_METADATA = [
  // CEO & Orchestrator
  { key: 'ceo_system', label: 'CEO: System Prompt', group: 'ceo', placeholder: 'You are the CEO...' },
  { key: 'planning_session', label: 'CEO: Planning Session Prompt', group: 'ceo', placeholder: 'Planning session orchestration...' },
  { key: 'monitoring_session', label: 'CEO: Monitoring Session Prompt', group: 'ceo', placeholder: 'Monitoring session orchestration...' },

  // Tasks & Review
  { key: 'issue_discovery', label: 'Tasks: Issue Discovery', group: 'tasks', placeholder: 'Discover repository issues...' },
  { key: 'pr_review', label: 'Tasks: PR Review', group: 'tasks', placeholder: 'Review Pull Request...' },
  { key: 'post_merge_qa', label: 'Tasks: Post-Merge QA', group: 'tasks', placeholder: 'Post merge QA analysis...' },
  { key: 'pr_conflict_resolution', label: 'Tasks: PR Conflict Resolution', group: 'tasks', placeholder: 'Resolve merge conflicts...' },

  // Jules Tasks
  { key: 'jules_implementation', label: 'Jules: Implementation', group: 'jules', placeholder: 'Jules implementation task...' },
  { key: 'jules_retry', label: 'Jules: Retry / Feedback', group: 'jules', placeholder: 'Jules retry feedback...' },
  { key: 'jules_pr_check_fix', label: 'Jules: PR Check Fix', group: 'jules', placeholder: 'Fix failing PR checks...' },
  { key: 'jules_pr_conflict_replacement', label: 'Jules: PR Conflict Replacement', group: 'jules', placeholder: 'Conflict replacement...' },

  // Planning Phase
  { key: 'planning_jules_sync', label: 'Planning: Jules Session Status Sync', group: 'planning', placeholder: 'Jules active/stalled check...' },
  { key: 'planning_pr_sync', label: 'Planning: PR Status Sync', group: 'planning', placeholder: 'PR conflict/CI check...' },
  { key: 'planning_analysis', label: 'Planning: Repository compass analysis', group: 'planning', placeholder: 'Repository analysis & blockers...' },
  { key: 'planning_proposal', label: 'Planning: Issue Proposal Logic', group: 'planning', placeholder: 'Formulating issue proposals...' },
  { key: 'planning_synthesis', label: 'Planning: Master Plan Synthesis & Priority Queue', group: 'planning', placeholder: 'Consolidating delegation order...' },

  // Monitoring Phase
  { key: 'monitor_sessions', label: 'Monitoring: Session Health Check', group: 'monitoring', placeholder: 'Active delegation health checks...' },
  { key: 'monitor_prs', label: 'Monitoring: PR Validation', group: 'monitoring', placeholder: 'PR validation and automatic fixing...' },
  { key: 'monitor_conflicts', label: 'Monitoring: Conflict Resolution', group: 'monitoring', placeholder: 'Automatic merge conflict resolving...' },
  { key: 'monitoring_synthesis', label: 'Monitoring: Status Evaluation', group: 'monitoring', placeholder: 'Consolidating monitoring results...' },

  // Audit Phase
  { key: 'audit_consistency', label: 'Audit: Data Consistency Check', group: 'audit', placeholder: 'Comparing state registry vs GitHub...' },
  { key: 'audit_performance', label: 'Audit: Performance Assessment', group: 'audit', placeholder: 'Assessing action history efficiency...' },
  { key: 'audit_synthesis', label: 'Audit: QA Manager Decision Matrix', group: 'audit', placeholder: 'Consolidating audit reports and remediation JSON...' },
];

export default function SettingsPage({ config: propConfig, registry: propRegistry, memoryStore, onSave, onMemoryRefresh }: Props) {
  // Lokale States für Formulare
  const [config, setConfig] = useState<AutopilotConfig | null>(null);
  const [registry, setRegistry] = useState<QuotaRegistry | null>(null);

  const [saving, setSaving] = useState(false);
  const [status, setStatus] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  // Props in lokalen State kopieren
  useEffect(() => {
    if (propConfig) {
      setConfig(JSON.parse(JSON.stringify(propConfig)));
    }
  }, [propConfig]);

  useEffect(() => {
    if (propRegistry) {
      setRegistry(JSON.parse(JSON.stringify(propRegistry)));
    }
  }, [propRegistry]);

  if (!config || !registry) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="w-8 h-8 text-purple-500 animate-spin" />
      </div>
    );
  }

  const handleConfigChange = (key: keyof AutopilotConfig, value: unknown) => {
    setConfig(prev => prev ? { ...prev, [key]: value } : null);
  };

  const handleNestedConfigChange = <T extends keyof AutopilotConfig>(
    parentKey: T,
    childKey: string,
    value: unknown
  ) => {
    setConfig(prev => {
      if (!prev) return null;
      const parent = prev[parentKey] as Record<string, unknown>;
      return {
        ...prev,
        [parentKey]: {
          ...parent,
          [childKey]: value
        } as unknown as AutopilotConfig[T]
      };
    });
  };

  const handleProviderChange = (providerKey: string, key: string, value: unknown) => {
    setRegistry(prev => {
      if (!prev) return null;
      const provider = prev.providers[providerKey];
      if (!provider) return prev;
      return {
        ...prev,
        providers: {
          ...prev.providers,
          [providerKey]: {
            ...provider,
            [key]: value
          }
        }
      };
    });
  };

  const handleRoutingChange = (taskType: string, value: string) => {
    setRegistry(prev => {
      if (!prev) return null;
      // Split by comma and trim whitespace
      const list = value.split(',').map(s => s.trim()).filter(s => s.length > 0);
      return {
        ...prev,
        routing_rules: {
          ...prev.routing_rules,
          [taskType]: list
        }
      };
    });
  };

  const handleDualCeoArrayChange = (key: 'ceo_alpha_chain' | 'ceo_beta_chain' | 'deliberation_tasks', value: string) => {
    const list = value.split(',').map(s => s.trim()).filter(s => s.length > 0);
    handleNestedConfigChange('dual_ceo', key, list);
  };

  const handleWorkingSessionsArrayChange = (key: 'preferred_agents', value: string) => {
    const list = value.split(',').map(s => s.trim()).filter(s => s.length > 0);
    handleNestedConfigChange('working_sessions', key, list);
  };

  const handlePromptChange = (key: string, value: string) => {
    setConfig(prev => {
      if (!prev) return null;
      const prompts = prev.prompts || {};
      return {
        ...prev,
        prompts: {
          ...prompts,
          [key]: value
        }
      };
    });
  };

  const handleProviderModelChange = (providerKey: string, modelKey: string, key: 'name' | 'estimated_cost_per_call_usd', value: unknown) => {
    setRegistry(prev => {
      if (!prev) return null;
      const provider = prev.providers[providerKey];
      if (!provider) return prev;
      return {
        ...prev,
        providers: {
          ...prev.providers,
          [providerKey]: {
            ...provider,
            models: {
              ...(provider.models || {}),
              [modelKey]: {
                ...(provider.models?.[modelKey] || { name: '', estimated_cost_per_call_usd: 0 }),
                [key]: value
              }
            }
          }
        }
      };
    });
  };

  const handleSave = async () => {
    setSaving(true);
    setStatus(null);
    try {
      // 1. Speichere Autopilot Config
      const configRes = await fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(config)
      });
      if (!configRes.ok) {
        const errData = await configRes.json();
        throw new Error(`Autopilot-Konfiguration fehlgeschlagen: ${errData.message || configRes.statusText}`);
      }

      // 2. Speichere Quota/Registry Config
      const quotaRes = await fetch('/api/quota', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(registry)
      });
      if (!quotaRes.ok) {
        const errData = await quotaRes.json();
        throw new Error(`Quota-Konfiguration fehlgeschlagen: ${errData.message || quotaRes.statusText}`);
      }

      setStatus({ type: 'success', message: 'Einstellungen erfolgreich gespeichert!' });
      onSave(); // Refresh Parent Data

      // Auto-clear success message after 4s
      setTimeout(() => {
        setStatus(null);
      }, 4000);
    } catch (err) {
      setStatus({ type: 'error', message: err instanceof Error ? err.message : 'Unbekannter Fehler beim Speichern' });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-6 animate-in pb-12">
      {/* Header mit Save-Button */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-slate-900/40 p-4 border border-slate-700/30 rounded-2xl">
        <div>
          <h2 className="text-xl font-bold gradient-text flex items-center gap-2">
            <Settings className="w-5 h-5 text-purple-400" />
            System-Konfiguration
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Autopilot-Intervalle, Jules-Verhalten, Token-Budgets und LLM-Routing
          </p>
        </div>
        <button
          onClick={handleSave}
          disabled={saving}
          className="btn-primary flex items-center gap-2 w-full sm:w-auto justify-center disabled:opacity-50"
        >
          {saving ? (
            <>
              <Loader2 className="w-4 h-4 animate-spin" />
              Speichern...
            </>
          ) : (
            <>
              <Save className="w-4 h-4" />
              Änderungen Speichern
            </>
          )}
        </button>
      </div>

      {/* Status Alerts */}
      {status && (
        <div className={`p-4 rounded-xl border flex items-start gap-3 ${
          status.type === 'success'
            ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400'
            : 'bg-red-500/10 border-red-500/30 text-red-400'
        }`}>
          {status.type === 'success' ? (
            <Check className="w-5 h-5 mt-0.5 flex-shrink-0" />
          ) : (
            <AlertCircle className="w-5 h-5 mt-0.5 flex-shrink-0" />
          )}
          <div>
            <div className="font-semibold text-sm">
              {status.type === 'success' ? 'Erfolg' : 'Fehler beim Speichern'}
            </div>
            <div className="text-xs mt-0.5 opacity-90">{status.message}</div>
          </div>
        </div>
      )}

      {/* Forms Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Linke Spalte: Autopilot & Jules */}
        <div className="space-y-6">
          {/* Card: Autopilot Core */}
          <div className="glass-card p-6">
            <h3 className="text-base font-semibold text-slate-200 border-b border-slate-700/50 pb-3 mb-4 flex items-center gap-2">
              <Cpu className="w-4 h-4 text-cyan-400" />
              Autopilot Core
            </h3>
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-slate-400 mb-1.5">GitHub Repository</label>
                <input
                  type="text"
                  value={config.repository}
                  onChange={(e: any) => handleConfigChange('repository', e.target.value)}
                  className="input-field"
                  placeholder="Owner/Repo"
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Planungs-Intervall (Minuten)</label>
                  <input
                    type="number"
                    value={config.wake_intervals.planning_minutes}
                    onChange={(e: any) => handleNestedConfigChange('wake_intervals', 'planning_minutes', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="1"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Monitoring-Intervall (Minuten)</label>
                  <input
                    type="number"
                    value={config.wake_intervals.monitoring_minutes}
                    onChange={(e: any) => handleNestedConfigChange('wake_intervals', 'monitoring_minutes', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="1"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Optimizer-Intervall (Stunden)</label>
                  <input
                    type="number"
                    value={config.wake_intervals.optimizer_hours ?? 12}
                    onChange={(e: any) => handleNestedConfigChange('wake_intervals', 'optimizer_hours', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="1"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Memory-Optimierung (jeden x. Lauf)</label>
                  <input
                    type="number"
                    value={config.wake_intervals.memory_optimization_runs ?? 3}
                    onChange={(e: any) => handleNestedConfigChange('wake_intervals', 'memory_optimization_runs', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="1"
                  />
                </div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Gemini Worktree Pfad</label>
                  <input
                    type="text"
                    value={config.gemini_worktree_path}
                    onChange={(e: any) => handleConfigChange('gemini_worktree_path', e.target.value)}
                    className="input-field"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Max. Issues pro Planungs-Zyklus</label>
                  <input
                    type="number"
                    value={config.max_issues_per_planning_cycle}
                    onChange={(e: any) => handleConfigChange('max_issues_per_planning_cycle', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="1"
                  />
                </div>
              </div>
            </div>
          </div>

          {/* Card: Jules Session Management */}
          <div className="glass-card p-6">
            <h3 className="text-base font-semibold text-slate-200 border-b border-slate-700/50 pb-3 mb-4 flex items-center gap-2">
              <Shield className="w-4 h-4 text-purple-400" />
              Jules Orchestrierung
            </h3>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Max. Tägliche Sessions</label>
                  <input
                    type="number"
                    value={config.jules.max_daily_sessions}
                    onChange={(e: any) => handleNestedConfigChange('jules', 'max_daily_sessions', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="1"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Max. Gleichzeitige Sessions</label>
                  <input
                    type="number"
                    value={config.jules.max_concurrent_sessions}
                    onChange={(e: any) => handleNestedConfigChange('jules', 'max_concurrent_sessions', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="1"
                  />
                </div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Max. Feedback Auto-Retries</label>
                  <input
                    type="number"
                    value={config.jules.auto_retry_feedback_max}
                    onChange={(e: any) => handleNestedConfigChange('jules', 'auto_retry_feedback_max', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="0"
                  />
                </div>
                <div className="flex items-center h-full pt-6">
                  <label className="relative flex items-center gap-2.5 cursor-pointer select-none">
                    <input
                      type="checkbox"
                      checked={config.jules.auto_approve_plans}
                      onChange={(e: any) => handleNestedConfigChange('jules', 'auto_approve_plans', e.target.checked)}
                      className="w-4 h-4 rounded border-slate-600 bg-slate-900 text-purple-600 focus:ring-purple-500/50"
                    />
                    <span className="text-xs font-medium text-slate-300">Implementierungspläne automatisch freigeben</span>
                  </label>
                </div>
              </div>
            </div>
          </div>

          {/* Card: Working Sessions */}
          <div className="glass-card p-6">
            <h3 className="text-base font-semibold text-slate-200 border-b border-slate-700/50 pb-3 mb-4 flex items-center gap-2">
              <Zap className="w-4 h-4 text-amber-400" />
              Working Sessions
            </h3>
            <div className="space-y-4">
              <label className="relative flex items-center gap-2.5 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={config.working_sessions?.enabled ?? true}
                  onChange={(e: any) => handleNestedConfigChange('working_sessions', 'enabled', e.target.checked)}
                  className="w-4 h-4 rounded border-slate-600 bg-slate-900 text-amber-500 focus:ring-amber-500/50"
                />
                <span className="text-xs font-semibold text-slate-300">Zusätzliche Working Sessions aktivieren</span>
              </label>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-1.5">Max. gleichzeitige Working Sessions</label>
                  <input
                    type="number"
                    value={config.working_sessions?.max_concurrent ?? 3}
                    onChange={(e: any) => handleNestedConfigChange('working_sessions', 'max_concurrent', parseInt(e.target.value) || 0)}
                    className="input-field"
                    min="0"
                  />
                </div>
                <label className="relative flex items-center gap-2.5 cursor-pointer select-none pt-6">
                  <input
                    type="checkbox"
                    checked={config.working_sessions?.queue_non_jules_agent_issues ?? true}
                    onChange={(e: any) => handleNestedConfigChange('working_sessions', 'queue_non_jules_agent_issues', e.target.checked)}
                    className="w-4 h-4 rounded border-slate-600 bg-slate-900 text-amber-500 focus:ring-amber-500/50"
                  />
                  <span className="text-xs font-medium text-slate-300">Lokale Agent-Issues erst in Working Queue legen</span>
                </label>
              </div>
              <div>
                <label className="block text-xs font-medium text-slate-400 mb-1.5">Bevorzugte Working-Session Agents</label>
                <input
                  type="text"
                  value={config.working_sessions?.preferred_agents?.join(', ') || ''}
                  onChange={(e: any) => handleWorkingSessionsArrayChange('preferred_agents', e.target.value)}
                  className="input-field font-mono text-xs"
                  placeholder="codex_orchestrator, gemini_cli, copilot_cli, cline_cli"
                />
              </div>
            </div>
          </div>

          {/* Card: Issue Filter */}
          <div className="glass-card p-6">
            <h3 className="text-base font-semibold text-slate-200 border-b border-slate-700/50 pb-3 mb-4 flex items-center gap-2">
              <ListFilter className="w-4 h-4 text-emerald-400" />
              GitHub Issue Filter
            </h3>
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-slate-400 mb-1.5">
                  Berücksichtigte Labels (kommagetrennt)
                </label>
                <input
                  type="text"
                  value={config.issue_filters.include_labels.join(', ')}
                  onChange={(e: any) => handleNestedConfigChange('issue_filters', 'include_labels', e.target.value.split(',').map((s: string) => s.trim()).filter((s: string) => s.length > 0))}
                  className="input-field"
                  placeholder="z.B. jules-task, bug, priority: critical"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-slate-400 mb-1.5">
                  Ausgeschlossene Labels (kommagetrennt)
                </label>
                <input
                  type="text"
                  value={config.issue_filters.exclude_labels.join(', ')}
                  onChange={(e: any) => handleNestedConfigChange('issue_filters', 'exclude_labels', e.target.value.split(',').map((s: string) => s.trim()).filter((s: string) => s.length > 0))}
                  className="input-field"
                  placeholder="z.B. wontfix, duplicate, on-hold"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-slate-400 mb-1.5">Autopilot Kennzeichnungs-Label</label>
                <input
                  type="text"
                  value={config.issue_filters.autopilot_label}
                  onChange={(e: any) => handleNestedConfigChange('issue_filters', 'autopilot_label', e.target.value)}
                  className="input-field"
                  placeholder="autopilot-created"
                />
              </div>
            </div>
          </div>

          {/* Card: CEO + QA Manager Deliberation */}
          {config.dual_ceo && (
            <div className="glass-card p-6">
              <h3 className="text-base font-semibold text-slate-200 border-b border-slate-700/50 pb-3 mb-4 flex items-center gap-2">
                <Users className="w-4 h-4 text-purple-400" />
                CEO + QA Manager Deliberation
              </h3>
              <p className="text-xs text-slate-400 mb-4 leading-relaxed">
                Strukturierte Abstimmung zwischen CEO und QA Manager bei wichtigen Aufgaben wie Planung, Audit und komplexen Code-Reviews.
              </p>
              <div className="space-y-4">
                <div className="flex items-center mb-2">
                  <label className="relative flex items-center gap-2.5 cursor-pointer select-none">
                    <input
                      type="checkbox"
                      checked={config.dual_ceo.enabled}
                      onChange={(e: any) => handleNestedConfigChange('dual_ceo', 'enabled', e.target.checked)}
                      className="w-4 h-4 rounded border-slate-600 bg-slate-900 text-purple-600 focus:ring-purple-500/50"
                    />
                    <span className="text-xs font-semibold text-slate-300">CEO + QA Manager Modus aktivieren</span>
                  </label>
                </div>

                <div className="grid grid-cols-1 gap-4">
                  <div>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5">
                      CEO Fallback-Kette (Kommagetrennt)
                    </label>
                    <input
                      type="text"
                      value={config.dual_ceo.ceo_alpha_chain?.join(', ') || ''}
                      onChange={(e: any) => handleDualCeoArrayChange('ceo_alpha_chain', e.target.value)}
                      className="input-field py-1.5 px-3 text-xs font-mono"
                      placeholder="z.B. codex_orchestrator:planning, claude_code:balanced"
                      disabled={!config.dual_ceo.enabled}
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5">
                      QA Manager Fallback-Kette (Kommagetrennt)
                    </label>
                    <input
                      type="text"
                      value={config.dual_ceo.ceo_beta_chain?.join(', ') || ''}
                      onChange={(e: any) => handleDualCeoArrayChange('ceo_beta_chain', e.target.value)}
                      className="input-field py-1.5 px-3 text-xs font-mono"
                      placeholder="z.B. gemini_cli:balanced, kiro_cli:default"
                      disabled={!config.dual_ceo.enabled}
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5">Max. Diskussionsrunden</label>
                    <input
                      type="number"
                      value={config.dual_ceo.max_deliberation_rounds || 3}
                      onChange={(e: any) => handleNestedConfigChange('dual_ceo', 'max_deliberation_rounds', parseInt(e.target.value) || 0)}
                      className="input-field text-xs"
                      min="1"
                      max="5"
                      disabled={!config.dual_ceo.enabled}
                    />
                  </div>
                  <div className="flex flex-col justify-end space-y-2.5">
                    <label className="relative flex items-center gap-2 cursor-pointer select-none">
                      <input
                        type="checkbox"
                        checked={config.dual_ceo.fallback_to_single}
                        onChange={(e: any) => handleNestedConfigChange('dual_ceo', 'fallback_to_single', e.target.checked)}
                        className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-purple-600 focus:ring-purple-500/50"
                        disabled={!config.dual_ceo.enabled}
                      />
                      <span className="text-[11px] font-medium text-slate-300">Single-Agent Fallback</span>
                    </label>
                    <label className="relative flex items-center gap-2 cursor-pointer select-none">
                      <input
                        type="checkbox"
                        checked={config.dual_ceo.log_deliberations}
                        onChange={(e: any) => handleNestedConfigChange('dual_ceo', 'log_deliberations', e.target.checked)}
                        className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-purple-600 focus:ring-purple-500/50"
                        disabled={!config.dual_ceo.enabled}
                      />
                      <span className="text-[11px] font-medium text-slate-300">Protokolle loggen</span>
                    </label>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-medium text-slate-400 mb-2">Aktivierte Tasks für Deliberation</label>
                  <div className="grid grid-cols-2 gap-2 bg-slate-900/40 p-3 rounded-lg border border-slate-800">
                    {['planning', 'complex_review', 'code_review'].map((task) => {
                      const isChecked = config.dual_ceo.deliberation_tasks?.includes(task);
                      return (
                        <label key={task} className="relative flex items-center gap-2 cursor-pointer select-none">
                          <input
                            type="checkbox"
                            checked={isChecked}
                            onChange={(e) => {
                              const currentTasks = config.dual_ceo.deliberation_tasks || [];
                              const newTasks = e.target.checked
                                ? [...currentTasks, task]
                                : currentTasks.filter(t => t !== task);
                              handleNestedConfigChange('dual_ceo', 'deliberation_tasks', newTasks);
                            }}
                            className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-purple-600 focus:ring-purple-500/50"
                            disabled={!config.dual_ceo.enabled}
                          />
                          <span className="text-xs font-mono text-slate-300">{task}</span>
                        </label>
                      );
                    })}
                  </div>
                </div>
              </div>
            </div>
          )}
          {/* Card: System-Prompts */}
          <div className="glass-card p-6">
            <h3 className="text-base font-semibold text-slate-200 border-b border-slate-700/50 pb-3 mb-4 flex items-center gap-2">
              <Settings className="w-4 h-4 text-purple-400" />
              System-Prompts
            </h3>
            <p className="text-xs text-slate-400 mb-4 leading-relaxed">
              Passe die System-Prompts an, die der Autopilot für die verschiedenen Sessions verwendet.
            </p>
            <div className="space-y-6">
              {/* CEO Group */}
              <div className="space-y-4">
                <h4 className="text-xs font-bold uppercase tracking-wider text-rose-400">CEO & Orchestration</h4>
                {PROMPT_METADATA.filter(p => p.group === 'ceo').map(p => (
                  <div key={p.key}>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5 flex justify-between">
                      <span>{p.label}</span>
                      <span className="text-[10px] text-slate-500 font-mono">{p.key}</span>
                    </label>
                    <textarea
                      value={config.prompts?.[p.key] || ''}
                      onChange={(e) => handlePromptChange(p.key, e.target.value)}
                      className="input-field min-h-[80px] font-mono text-xs leading-normal"
                      rows={3}
                      placeholder={p.placeholder}
                    />
                  </div>
                ))}
              </div>

              {/* Planning Group */}
              <div className="space-y-4 pt-4 border-t border-slate-800/70">
                <h4 className="text-xs font-bold uppercase tracking-wider text-cyan-400">Planning-Phase (Planung)</h4>
                {PROMPT_METADATA.filter(p => p.group === 'planning').map(p => (
                  <div key={p.key}>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5 flex justify-between">
                      <span>{p.label}</span>
                      <span className="text-[10px] text-slate-500 font-mono">{p.key}</span>
                    </label>
                    <textarea
                      value={config.prompts?.[p.key] || ''}
                      onChange={(e) => handlePromptChange(p.key, e.target.value)}
                      className="input-field min-h-[80px] font-mono text-xs leading-normal"
                      rows={3}
                      placeholder={p.placeholder}
                    />
                  </div>
                ))}
              </div>

              {/* Monitoring Group */}
              <div className="space-y-4 pt-4 border-t border-slate-800/70">
                <h4 className="text-xs font-bold uppercase tracking-wider text-purple-400">Monitoring-Phase (Überwachung)</h4>
                {PROMPT_METADATA.filter(p => p.group === 'monitoring').map(p => (
                  <div key={p.key}>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5 flex justify-between">
                      <span>{p.label}</span>
                      <span className="text-[10px] text-slate-500 font-mono">{p.key}</span>
                    </label>
                    <textarea
                      value={config.prompts?.[p.key] || ''}
                      onChange={(e) => handlePromptChange(p.key, e.target.value)}
                      className="input-field min-h-[80px] font-mono text-xs leading-normal"
                      rows={3}
                      placeholder={p.placeholder}
                    />
                  </div>
                ))}
              </div>

              {/* Audit Group */}
              <div className="space-y-4 pt-4 border-t border-slate-800/70">
                <h4 className="text-xs font-bold uppercase tracking-wider text-amber-400">Audit-Phase (Prüfung)</h4>
                {PROMPT_METADATA.filter(p => p.group === 'audit').map(p => (
                  <div key={p.key}>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5 flex justify-between">
                      <span>{p.label}</span>
                      <span className="text-[10px] text-slate-500 font-mono">{p.key}</span>
                    </label>
                    <textarea
                      value={config.prompts?.[p.key] || ''}
                      onChange={(e) => handlePromptChange(p.key, e.target.value)}
                      className="input-field min-h-[80px] font-mono text-xs leading-normal"
                      rows={3}
                      placeholder={p.placeholder}
                    />
                  </div>
                ))}
              </div>

              {/* Tasks Group */}
              <div className="space-y-4 pt-4 border-t border-slate-800/70">
                <h4 className="text-xs font-bold uppercase tracking-wider text-green-400">Tasks & Code Review</h4>
                {PROMPT_METADATA.filter(p => p.group === 'tasks').map(p => (
                  <div key={p.key}>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5 flex justify-between">
                      <span>{p.label}</span>
                      <span className="text-[10px] text-slate-500 font-mono">{p.key}</span>
                    </label>
                    <textarea
                      value={config.prompts?.[p.key] || ''}
                      onChange={(e) => handlePromptChange(p.key, e.target.value)}
                      className="input-field min-h-[80px] font-mono text-xs leading-normal"
                      rows={3}
                      placeholder={p.placeholder}
                    />
                  </div>
                ))}
              </div>

              {/* Jules Group */}
              <div className="space-y-4 pt-4 border-t border-slate-800/70">
                <h4 className="text-xs font-bold uppercase tracking-wider text-blue-400">Jules Sessions</h4>
                {PROMPT_METADATA.filter(p => p.group === 'jules').map(p => (
                  <div key={p.key}>
                    <label className="block text-xs font-medium text-slate-400 mb-1.5 flex justify-between">
                      <span>{p.label}</span>
                      <span className="text-[10px] text-slate-500 font-mono">{p.key}</span>
                    </label>
                    <textarea
                      value={config.prompts?.[p.key] || ''}
                      onChange={(e) => handlePromptChange(p.key, e.target.value)}
                      className="input-field min-h-[80px] font-mono text-xs leading-normal"
                      rows={3}
                      placeholder={p.placeholder}
                    />
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Rechte Spalte: Provider & Routing */}
        <div className="space-y-6">
          {/* Card: API Provider Quotas */}
          <div className="glass-card p-6">
            <h3 className="text-base font-semibold text-slate-200 border-b border-slate-700/50 pb-3 mb-4 flex items-center gap-2">
              <Cpu className="w-4 h-4 text-purple-400" />
              API Provider Quotas
            </h3>
            <div className="space-y-4 max-h-[380px] overflow-y-auto pr-1">
              {Object.entries(registry.providers).map(([pKey, pVal]: [string, any]) => (
                <div key={pKey} className="p-3 bg-slate-900/40 border border-slate-800 rounded-xl space-y-3">
                  <div className="flex justify-between items-center">
                    <span className="text-xs font-semibold text-slate-200">{PROVIDER_LABELS[pKey] || pKey}</span>
                    <label className="relative flex items-center gap-2 cursor-pointer select-none">
                      <input
                        type="checkbox"
                        checked={pVal.enabled}
                        onChange={(e: any) => handleProviderChange(pKey, 'enabled', e.target.checked)}
                        className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-purple-600 focus:ring-purple-500/50"
                      />
                      <span className="text-[11px] font-medium text-slate-400">Aktiv</span>
                    </label>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-[10px] font-medium text-slate-500 mb-1">Aufruflimit (Täglich)</label>
                      <input
                        type="number"
                        value={pVal.daily_limit}
                        onChange={(e: any) => handleProviderChange(pKey, 'daily_limit', parseInt(e.target.value) || 0)}
                        className="input-field py-1 px-2.5 text-xs"
                        min="0"
                        disabled={!pVal.enabled}
                      />
                    </div>
                    <div>
                      <label className="block text-[10px] font-medium text-slate-500 mb-1">Budget in USD (Täglich)</label>
                      <input
                        type="number"
                        value={pVal.daily_budget_usd ?? 0}
                        onChange={(e: any) => handleProviderChange(pKey, 'daily_budget_usd', parseFloat(e.target.value) || 0)}
                        className="input-field py-1 px-2.5 text-xs"
                        min="0"
                        step="0.01"
                        disabled={!pVal.enabled}
                      />
                    </div>
                  </div>
                  {pVal.models && Object.keys(pVal.models).length > 0 && (
                    <div className="space-y-2 pt-2 border-t border-slate-800/70">
                      <div className="text-[10px] uppercase tracking-wide text-slate-500 font-semibold">Modelle (Model Auswahl)</div>
                      {Object.entries(pVal.models).map(([modelKey, modelVal]: [string, any]) => (
                        <div key={modelKey} className="grid grid-cols-[88px_1fr_90px] gap-2 items-center">
                          <span className="text-[10px] text-slate-400 font-mono">{modelKey}</span>
                          <input
                            type="text"
                            value={modelVal.name || ''}
                            onChange={(e: any) => handleProviderModelChange(pKey, modelKey, 'name', e.target.value)}
                            className="input-field py-1 px-2.5 text-xs font-mono"
                            disabled={!pVal.enabled}
                          />
                          <input
                            type="number"
                            value={modelVal.estimated_cost_per_call_usd ?? 0}
                            onChange={(e: any) => handleProviderModelChange(pKey, modelKey, 'estimated_cost_per_call_usd', parseFloat(e.target.value) || 0)}
                            className="input-field py-1 px-2.5 text-xs"
                            min="0"
                            step="0.01"
                            disabled={!pVal.enabled}
                          />
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Card: Task-Routing Rules */}
          <div className="glass-card p-6">
            <h3 className="text-base font-semibold text-slate-200 border-b border-slate-700/50 pb-3 mb-3 flex items-center gap-2">
              <Layers className="w-4 h-4 text-cyan-400" />
              Routing-Regeln (LLM-Ketten)
            </h3>
            <p className="text-xs text-slate-400 mb-5 leading-relaxed">
              Definiert die Ausweich-Reihenfolge (Fallback-Chain) der KI-Modelle für verschiedene System-Tasks.
              Die Angabe erfolgt als kommagetrennte Liste von Providern (z. B. <code>gemini_cli, claude_code</code>).
              Schlägt ein Provider fehl oder ist sein Tages-Budget erschöpft, wird automatisch der nächste in der Kette aufgerufen.
            </p>
            <div className="space-y-4 max-h-[380px] overflow-y-auto pr-1">
              {Object.entries(registry.routing_rules).map(([taskType, chain]: [string, any]) => (
                <div key={taskType} className="border-b border-slate-800/40 pb-3.5 last:border-0 last:pb-0">
                  <div className="flex justify-between items-center mb-1">
                    <label className="block text-xs font-semibold text-slate-300 capitalize">
                      {taskType.replace(/_/g, ' ')}
                    </label>
                    <span className="text-[9px] text-slate-500 font-mono bg-slate-900 px-1.5 py-0.5 rounded border border-slate-800">{taskType}</span>
                  </div>
                  {ROUTING_DESCRIPTIONS[taskType] && (
                    <p className="text-[10px] text-slate-400 mb-2 leading-relaxed">
                      {ROUTING_DESCRIPTIONS[taskType]}
                    </p>
                  )}
                  <input
                    type="text"
                    value={chain.join(', ')}
                    onChange={(e: any) => handleRoutingChange(taskType, e.target.value)}
                    className="input-field py-1.5 px-3 text-xs font-mono"
                    placeholder="z.B. provider:model, provider:model"
                  />
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Memory System */}
      <MemoryPanel store={memoryStore} onRefresh={onMemoryRefresh} />
    </div>
  );
}
