import { useEffect, useState } from 'react';
import { AlertCircle, Check, ChevronDown, ChevronRight, Cpu, Layers, Loader2, Save, Settings, Shield } from 'lucide-react';
import type { AutopilotConfig, QuotaRegistry, MemoryStore, RunUnitSettings } from '../types';
import MemoryPanel from './MemoryPanel';

interface Props {
  config: AutopilotConfig;
  registry: QuotaRegistry;
  memoryStore: MemoryStore;
  onSave: () => void;
  onMemoryRefresh: () => void;
}

interface PartRunCatalog {
  name: string;
  label: string;
  script: string;
  description?: string;
}

interface SubRunCatalog {
  id: string;
  name: string;
  label: string;
  script: string;
  enabled: boolean;
  description?: string;
  part_runs: PartRunCatalog[];
}

interface MainRunCatalog {
  name: string;
  actualName: string;
  label: string;
  routerKey: string;
  intervalKey: keyof AutopilotConfig['wake_intervals'];
  description?: string;
  sub_runs: SubRunCatalog[];
  part_run_count: number;
}

interface RunCatalog {
  main_runs: MainRunCatalog[];
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

function splitChain(value: string): string[] {
  return value.split(',').map(item => item.trim()).filter(Boolean);
}

function joinChain(value?: string[]): string {
  return (value || []).join(', ');
}

function settingWithFallback(settings: RunUnitSettings | undefined, fallback?: string): RunUnitSettings {
  return {
    description: fallback || '',
    system_prompt: '',
    llm_chain: [],
    llm_provider: '',
    llm_model: '',
    allow_parallel: false,
    max_parallel: 1,
    ...settings,
  };
}

export default function SettingsPage({ config: propConfig, registry: propRegistry, memoryStore, onSave, onMemoryRefresh }: Props) {
  const [config, setConfig] = useState<AutopilotConfig | null>(null);
  const [registry, setRegistry] = useState<QuotaRegistry | null>(null);
  const [catalog, setCatalog] = useState<RunCatalog>({ main_runs: [] });
  const [expandedMain, setExpandedMain] = useState<Record<string, boolean>>({});
  const [expandedSub, setExpandedSub] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState(false);
  const [status, setStatus] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  useEffect(() => {
    setConfig(JSON.parse(JSON.stringify(propConfig)));
  }, [propConfig]);

  useEffect(() => {
    setRegistry(JSON.parse(JSON.stringify(propRegistry)));
  }, [propRegistry]);

  useEffect(() => {
    fetch('/run-catalog.json')
      .then(res => res.json())
      .then(setCatalog)
      .catch(() => setCatalog({ main_runs: [] }));
  }, []);

  if (!config || !registry) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="w-8 h-8 text-purple-500 animate-spin" />
      </div>
    );
  }

  const providerKeys = Object.keys(registry.providers || {});

  const updateConfig = (updater: (current: AutopilotConfig) => AutopilotConfig) => {
    setConfig(prev => prev ? updater(prev) : prev);
  };

  const updateRegistry = (updater: (current: QuotaRegistry) => QuotaRegistry) => {
    setRegistry(prev => prev ? updater(prev) : prev);
  };

  const updateRunSetting = (scope: 'main_runs' | 'sub_runs' | 'part_runs', name: string, patch: Partial<RunUnitSettings>) => {
    updateConfig(current => ({
      ...current,
      run_settings: {
        ...current.run_settings,
        [scope]: {
          ...(current.run_settings?.[scope] || {}),
          [name]: {
            ...(current.run_settings?.[scope]?.[name] || {}),
            ...patch,
          },
        },
      },
    }));
  };

  const updateSubEnabled = (mainRun: MainRunCatalog, subRun: SubRunCatalog, enabled: boolean) => {
    updateConfig(current => ({
      ...current,
      router_rules: {
        ...(current.router_rules || {}),
        [mainRun.routerKey]: (current.router_rules?.[mainRun.routerKey] || []).map(rule =>
          rule.name === subRun.label || rule.script === subRun.script ? { ...rule, enabled } : rule
        ),
      },
      run_settings: {
        ...current.run_settings,
        sub_runs: {
          ...(current.run_settings?.sub_runs || {}),
          [subRun.name]: {
            ...(current.run_settings?.sub_runs?.[subRun.name] || {}),
            enabled,
          },
        },
      },
    }));
  };

  const updateWakeInterval = (key: keyof AutopilotConfig['wake_intervals'], value: number) => {
    updateConfig(current => ({
      ...current,
      wake_intervals: {
        ...current.wake_intervals,
        [key]: value,
      },
    }));
  };

  const updateProvider = (providerKey: string, key: string, value: unknown) => {
    updateRegistry(current => ({
      ...current,
      providers: {
        ...current.providers,
        [providerKey]: {
          ...current.providers[providerKey],
          [key]: value,
        },
      },
    }));
  };

  const updateProviderModel = (providerKey: string, modelKey: string, key: 'name' | 'estimated_cost_per_call_usd', value: unknown) => {
    updateRegistry(current => ({
      ...current,
      providers: {
        ...current.providers,
        [providerKey]: {
          ...current.providers[providerKey],
          models: {
            ...(current.providers[providerKey].models || {}),
            [modelKey]: {
              ...(current.providers[providerKey].models?.[modelKey] || { name: '', estimated_cost_per_call_usd: 0 }),
              [key]: value,
            },
          },
        },
      },
    }));
  };

  const updateDualCeo = (key: keyof AutopilotConfig['dual_ceo'], value: unknown) => {
    updateConfig(current => ({
      ...current,
      dual_ceo: {
        ...current.dual_ceo,
        [key]: value,
      },
    }));
  };

  const handleSave = async () => {
    setSaving(true);
    setStatus(null);
    try {
      const configRes = await fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(config),
      });
      if (!configRes.ok) throw new Error((await configRes.json()).message || 'Autopilot-Konfiguration konnte nicht gespeichert werden.');

      const quotaRes = await fetch('/api/quota', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(registry),
      });
      if (!quotaRes.ok) throw new Error((await quotaRes.json()).message || 'Quota-Konfiguration konnte nicht gespeichert werden.');

      setStatus({ type: 'success', message: 'RUN-Konfiguration gespeichert.' });
      onSave();
    } catch (err) {
      setStatus({ type: 'error', message: err instanceof Error ? err.message : 'Unbekannter Fehler beim Speichern.' });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-6 animate-in pb-12">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-slate-900/40 p-4 border border-slate-700/30 rounded-2xl">
        <div>
          <h2 className="text-xl font-bold gradient-text flex items-center gap-2">
            <Settings className="w-5 h-5 text-purple-400" />
            System-Konfiguration
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            RUN-Struktur, SUB/PART-RUN Prompts, LLM-Ketten, Provider-Quotas und Governance.
          </p>
        </div>
        <button onClick={handleSave} disabled={saving} className="btn-primary flex items-center gap-2 w-full sm:w-auto justify-center disabled:opacity-50">
          {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
          {saving ? 'Speichern...' : 'Änderungen speichern'}
        </button>
      </div>

      {status && (
        <div className={`p-4 rounded-xl border flex items-start gap-3 ${status.type === 'success' ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400' : 'bg-red-500/10 border-red-500/30 text-red-400'}`}>
          {status.type === 'success' ? <Check className="w-5 h-5 mt-0.5" /> : <AlertCircle className="w-5 h-5 mt-0.5" />}
          <div>
            <div className="font-semibold text-sm">{status.type === 'success' ? 'Gespeichert' : 'Fehler'}</div>
            <div className="text-xs mt-0.5 opacity-90">{status.message}</div>
          </div>
        </div>
      )}

      <div className="glass-card p-6">
        <div className="border-b border-slate-700/50 pb-4 mb-5">
          <h3 className="text-base font-semibold text-slate-200 flex items-center gap-2">
            <Layers className="w-4 h-4 text-cyan-400" />
            RUN-Struktur & LLM-Konfiguration
          </h3>
          <p className="text-xs text-slate-400 mt-2 leading-relaxed">
            Diese Ansicht ist die zentrale Konfiguration für alle MAIN-, SUB- und PART-RUNs. Lange globale Prompts werden hier durch kurze, zuständige Prompts je Teilschritt ersetzt.
          </p>
        </div>

        <div className="space-y-4">
          {catalog.main_runs.map(mainRun => {
            const mainSettings = settingWithFallback(config.run_settings?.main_runs?.[mainRun.actualName], mainRun.description);
            const isOpen = expandedMain[mainRun.actualName] || false;
            return (
              <div key={mainRun.actualName} className="rounded-xl border border-slate-800 bg-slate-950/30 overflow-hidden">
                <div className="p-4">
                  <div className="grid grid-cols-1 xl:grid-cols-[1fr_160px_190px_160px] gap-4 items-center">
                    <button
                      type="button"
                      onClick={() => setExpandedMain(prev => ({ ...prev, [mainRun.actualName]: !isOpen }))}
                      className="flex items-start gap-3 text-left"
                    >
                      <span className="mt-1 text-slate-500">{isOpen ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}</span>
                      <span>
                        <span className="block text-lg font-semibold text-slate-100">{mainRun.label}</span>
                        <span className="block text-[11px] font-mono text-slate-500">{mainRun.actualName}</span>
                        <span className="block text-xs text-slate-400 mt-1">{mainSettings.description || 'Keine Beschreibung hinterlegt.'}</span>
                      </span>
                    </button>

                    <div>
                      <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">Intervall</label>
                      <input
                        type="number"
                        min="1"
                        value={config.wake_intervals[mainRun.intervalKey] || 1}
                        onChange={event => updateWakeInterval(mainRun.intervalKey, parseInt(event.target.value, 10) || 1)}
                        className="input-field py-1.5 text-xs"
                      />
                    </div>

                    <div className="grid grid-cols-2 gap-2">
                      <label className="flex items-center gap-2 text-xs text-slate-300 pt-5">
                        <input
                          type="checkbox"
                          checked={mainSettings.allow_parallel || false}
                          onChange={event => updateRunSetting('main_runs', mainRun.actualName, { allow_parallel: event.target.checked })}
                          className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-cyan-600"
                        />
                        Parallel erlauben
                      </label>
                      <div>
                        <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">Max parallel</label>
                        <input
                          type="number"
                          min="1"
                          value={mainSettings.max_parallel || 1}
                          onChange={event => updateRunSetting('main_runs', mainRun.actualName, { max_parallel: parseInt(event.target.value, 10) || 1 })}
                          className="input-field py-1.5 text-xs"
                        />
                      </div>
                    </div>

                    <div className="rounded-lg border border-slate-800 bg-slate-900/50 p-3 text-xs">
                      <div className="text-slate-400">SUB-RUNs: <span className="text-slate-100 font-semibold">{mainRun.sub_runs.length}</span></div>
                      <div className="text-slate-400 mt-1">PART-RUNs: <span className="text-slate-100 font-semibold">{mainRun.part_run_count}</span></div>
                    </div>
                  </div>
                </div>

                {isOpen && (
                  <div className="border-t border-slate-800 p-4 space-y-3">
                    {mainRun.sub_runs.map(subRun => {
                      const subSettings = settingWithFallback(config.run_settings?.sub_runs?.[subRun.name], subRun.description);
                      const subEnabled = (config.router_rules?.[mainRun.routerKey] || []).find(rule => rule.script === subRun.script || rule.name === subRun.label)?.enabled !== false;
                      const subOpen = expandedSub[subRun.name] || false;
                      return (
                        <div key={subRun.name} className="rounded-lg border border-slate-800 bg-slate-900/40">
                          <div className="p-3 space-y-3">
                            <div className="flex flex-wrap items-start justify-between gap-3">
                              <button type="button" onClick={() => setExpandedSub(prev => ({ ...prev, [subRun.name]: !subOpen }))} className="flex items-start gap-2 text-left">
                                <span className="mt-0.5 text-slate-500">{subOpen ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}</span>
                                <span>
                                  <span className="text-sm font-semibold text-slate-100">{subRun.label}</span>
                                  <span className="block text-[10px] font-mono text-slate-500">{subRun.name}</span>
                                </span>
                              </button>
                              <label className="flex items-center gap-2 text-xs text-slate-300">
                                <input
                                  type="checkbox"
                                  checked={subEnabled}
                                  onChange={event => updateSubEnabled(mainRun, subRun, event.target.checked)}
                                  className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-cyan-600"
                                />
                                SUB aktiv
                              </label>
                            </div>

                            <RunUnitFields
                              settings={subSettings}
                              providerKeys={providerKeys}
                              onChange={patch => updateRunSetting('sub_runs', subRun.name, patch)}
                            />
                          </div>

                          {subOpen && (
                            <div className="border-t border-slate-800 p-3 space-y-3">
                              {subRun.part_runs.length === 0 ? (
                                <div className="text-xs text-slate-500">Keine PART-RUNs in der Ordnerstruktur gefunden.</div>
                              ) : subRun.part_runs.map(partRun => {
                                const partSettings = settingWithFallback(config.run_settings?.part_runs?.[partRun.name], partRun.description);
                                return (
                                  <div key={partRun.name} className="rounded-lg border border-slate-800 bg-slate-950/45 p-3 space-y-3">
                                    <div className="flex flex-wrap items-start justify-between gap-3">
                                      <div>
                                        <div className="text-sm font-semibold text-slate-200">{partRun.label}</div>
                                        <div className="text-[10px] font-mono text-slate-500">{partRun.name}</div>
                                      </div>
                                      <label className="flex items-center gap-2 text-xs text-slate-300">
                                        <input
                                          type="checkbox"
                                          checked={partSettings.enabled !== false}
                                          onChange={event => updateRunSetting('part_runs', partRun.name, { enabled: event.target.checked })}
                                          className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-cyan-600"
                                        />
                                        PART aktiv
                                      </label>
                                    </div>
                                    <RunUnitFields
                                      settings={partSettings}
                                      providerKeys={providerKeys}
                                      onChange={patch => updateRunSetting('part_runs', partRun.name, patch)}
                                    />
                                  </div>
                                );
                              })}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <div className="grid grid-cols-1 xl:grid-cols-2 gap-5 mt-6 pt-6 border-t border-slate-800">
          <ProviderQuotaPanel registry={registry} onProviderChange={updateProvider} onModelChange={updateProviderModel} />
          <GovernancePanel config={config} onChange={updateDualCeo} />
        </div>
      </div>

      <MemoryPanel store={memoryStore} onRefresh={onMemoryRefresh} />
    </div>
  );
}

function RunUnitFields({ settings, providerKeys, onChange }: {
  settings: RunUnitSettings;
  providerKeys: string[];
  onChange: (patch: Partial<RunUnitSettings>) => void;
}) {
  return (
    <div className="grid grid-cols-1 xl:grid-cols-2 gap-3">
      <div>
        <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">Kurze RUN-Beschreibung</label>
        <textarea
          value={settings.description || ''}
          onChange={event => onChange({ description: event.target.value })}
          className="input-field min-h-[70px] text-xs"
          placeholder="Ein Satz: Welche Teilaufgabe erledigt dieser Run?"
        />
      </div>
      <div>
        <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">Kurzer System-Prompt</label>
        <textarea
          value={settings.system_prompt || ''}
          onChange={event => onChange({ system_prompt: event.target.value })}
          className="input-field min-h-[70px] text-xs font-mono"
          placeholder="Kurz und spezifisch für genau diesen Teilschritt."
        />
      </div>
      <div>
        <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">Fallback LLM-Kette</label>
        <input
          type="text"
          value={joinChain(settings.llm_chain)}
          onChange={event => onChange({ llm_chain: splitChain(event.target.value) })}
          className="input-field py-1.5 text-xs font-mono"
          placeholder="gemini_cli:balanced, claude_code:balanced"
        />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">LLM Provider</label>
          <select
            value={settings.llm_provider || ''}
            onChange={event => onChange({ llm_provider: event.target.value })}
            className="input-field py-1.5 text-xs"
          >
            <option value="">Aus Fallback-Kette</option>
            {providerKeys.map(provider => <option key={provider} value={provider}>{PROVIDER_LABELS[provider] || provider}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">LLM Modell</label>
          <input
            type="text"
            value={settings.llm_model || ''}
            onChange={event => onChange({ llm_model: event.target.value })}
            className="input-field py-1.5 text-xs font-mono"
            placeholder="balanced / premium / Modell-ID"
          />
        </div>
      </div>
    </div>
  );
}

function ProviderQuotaPanel({ registry, onProviderChange, onModelChange }: {
  registry: QuotaRegistry;
  onProviderChange: (providerKey: string, key: string, value: unknown) => void;
  onModelChange: (providerKey: string, modelKey: string, key: 'name' | 'estimated_cost_per_call_usd', value: unknown) => void;
}) {
  return (
    <div className="rounded-xl border border-slate-800 bg-slate-950/30 p-4">
      <h4 className="text-sm font-semibold text-slate-200 flex items-center gap-2 mb-3">
        <Cpu className="w-4 h-4 text-purple-400" />
        API Provider Quotas
      </h4>
      <div className="space-y-3 max-h-[420px] overflow-y-auto pr-1">
        {Object.entries(registry.providers || {}).map(([providerKey, provider]: [string, any]) => (
          <div key={providerKey} className="rounded-lg border border-slate-800 bg-slate-900/40 p-3 space-y-3">
            <div className="flex justify-between items-center">
              <span className="text-xs font-semibold text-slate-200">{PROVIDER_LABELS[providerKey] || providerKey}</span>
              <label className="flex items-center gap-2 text-xs text-slate-400">
                <input type="checkbox" checked={provider.enabled} onChange={event => onProviderChange(providerKey, 'enabled', event.target.checked)} className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-purple-600" />
                Aktiv
              </label>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <input type="number" min="0" value={provider.daily_limit || 0} onChange={event => onProviderChange(providerKey, 'daily_limit', parseInt(event.target.value, 10) || 0)} className="input-field py-1.5 text-xs" placeholder="Daily calls" />
              <input type="number" min="0" step="0.01" value={provider.daily_budget_usd ?? 0} onChange={event => onProviderChange(providerKey, 'daily_budget_usd', parseFloat(event.target.value) || 0)} className="input-field py-1.5 text-xs" placeholder="Daily USD" />
            </div>
            {provider.models && (
              <div className="space-y-2">
                {Object.entries(provider.models).map(([modelKey, model]: [string, any]) => (
                  <div key={modelKey} className="grid grid-cols-[82px_1fr_82px] gap-2 items-center">
                    <span className="text-[10px] font-mono text-slate-500">{modelKey}</span>
                    <input value={model.name || ''} onChange={event => onModelChange(providerKey, modelKey, 'name', event.target.value)} className="input-field py-1 text-xs font-mono" />
                    <input type="number" min="0" step="0.01" value={model.estimated_cost_per_call_usd ?? 0} onChange={event => onModelChange(providerKey, modelKey, 'estimated_cost_per_call_usd', parseFloat(event.target.value) || 0)} className="input-field py-1 text-xs" />
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

function GovernancePanel({ config, onChange }: {
  config: AutopilotConfig;
  onChange: (key: keyof AutopilotConfig['dual_ceo'], value: unknown) => void;
}) {
  return (
    <div className="rounded-xl border border-slate-800 bg-slate-950/30 p-4">
      <h4 className="text-sm font-semibold text-slate-200 flex items-center gap-2 mb-3">
        <Shield className="w-4 h-4 text-rose-400" />
        CEO + QA Manager Governance
      </h4>
      <div className="space-y-3">
        <label className="flex items-center gap-2 text-xs text-slate-300">
          <input type="checkbox" checked={config.dual_ceo.enabled} onChange={event => onChange('enabled', event.target.checked)} className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-rose-600" />
          Deliberation aktiv
        </label>
        <div>
          <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">CEO Fallback-Kette</label>
          <input value={joinChain(config.dual_ceo.ceo_chain)} onChange={event => onChange('ceo_chain', splitChain(event.target.value))} className="input-field py-1.5 text-xs font-mono" />
        </div>
        <div>
          <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">QA Manager Fallback-Kette</label>
          <input value={joinChain(config.dual_ceo.qa_manager_chain)} onChange={event => onChange('qa_manager_chain', splitChain(event.target.value))} className="input-field py-1.5 text-xs font-mono" />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">Max Runden</label>
            <input type="number" min="1" value={config.dual_ceo.max_deliberation_rounds || 1} onChange={event => onChange('max_deliberation_rounds', parseInt(event.target.value, 10) || 1)} className="input-field py-1.5 text-xs" />
          </div>
          <div>
            <label className="block text-[10px] uppercase tracking-wide text-slate-500 mb-1">Deliberation Tasks</label>
            <input value={joinChain(config.dual_ceo.deliberation_tasks)} onChange={event => onChange('deliberation_tasks', splitChain(event.target.value))} className="input-field py-1.5 text-xs font-mono" />
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2 text-xs text-slate-300">
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={config.dual_ceo.fallback_to_single} onChange={event => onChange('fallback_to_single', event.target.checked)} className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-rose-600" />
            Single-Agent Fallback
          </label>
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={config.dual_ceo.log_deliberations} onChange={event => onChange('log_deliberations', event.target.checked)} className="w-3.5 h-3.5 rounded border-slate-700 bg-slate-900 text-rose-600" />
            Deliberation loggen
          </label>
        </div>
      </div>
    </div>
  );
}
