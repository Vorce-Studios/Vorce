import { useState } from 'react';
import { Brain, Plus, Trash2, Tag, AlertTriangle, Info, Shield, X } from 'lucide-react';
import type { MemoryEntry, MemoryStore } from '../types';

const PRIORITY_COLORS: Record<string, string> = {
  critical: 'bg-red-500/20 text-red-400 border-red-500/30',
  high: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
  medium: 'bg-cyan-500/20 text-cyan-400 border-cyan-500/30',
  low: 'bg-slate-500/20 text-slate-400 border-slate-500/30',
};
const PRIORITY_ICONS: Record<string, typeof AlertTriangle> = {
  critical: AlertTriangle,
  high: Shield,
  medium: Info,
  low: Info,
};

interface Props {
  store: MemoryStore;
  onRefresh: () => void;
}

export default function MemoryPanel({ store, onRefresh }: Props) {
  const [showAdd, setShowAdd] = useState(false);
  const [newText, setNewText] = useState('');
  const [newType, setNewType] = useState<'permanent' | 'temporary'>('temporary');
  const [newPriority, setNewPriority] = useState<string>('medium');
  const [filterType, setFilterType] = useState<'permanent' | 'temporary' | null>(null);
  const [saving, setSaving] = useState(false);

  const memories = store.memories || [];
  const filtered = filterType
    ? memories.filter(m => m.type === filterType)
    : memories;

  const handleAdd = async () => {
    if (!newText.trim()) return;
    setSaving(true);
    try {
      const entry: Omit<MemoryEntry, 'id' | 'created_at'> = {
        text: newText.trim(),
        type: newType,
        priority: newPriority as MemoryEntry['priority'],
        source: 'dashboard',
      };
      const res = await fetch('/api/memories', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'add', entry }),
      });
      if (res.ok) {
        setNewText('');
        setNewType('temporary');
        setNewPriority('medium');
        setShowAdd(false);
        onRefresh();
      }
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    const res = await fetch('/api/memories', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'remove', id }),
    });
    if (res.ok) onRefresh();
  };

  return (
    <div className="glass-card p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-base font-semibold text-slate-200 flex items-center gap-2">
          <Brain className="w-4 h-4 text-purple-400" />
          Memory-System ({memories.length}/30)
        </h3>
        <button
          onClick={() => setShowAdd(!showAdd)}
          className="btn-primary text-xs py-1.5 px-3 flex items-center gap-1.5"
        >
          {showAdd ? <X className="w-3.5 h-3.5" /> : <Plus className="w-3.5 h-3.5" />}
          {showAdd ? 'Abbrechen' : 'Erinnerung hinzufügen'}
        </button>
      </div>

      <p className="text-xs text-slate-400 mb-4 leading-relaxed">
        Gedächtnis-Einträge werden bei allen Zyklen und CEOs automatisch in den KI-Kontext injiziert, um den aktuellen Stand der Aufgaben zu teilen.
        Typ <code className="text-purple-400">permanent</code> = langlebige Richtlinien; Typ <code className="text-purple-400">temporary</code> = dynamischer Status.
      </p>

      {/* Type Filter */}
      <div className="flex flex-wrap gap-1.5 mb-4">
        <button
          onClick={() => setFilterType(null)}
          className={`text-[10px] px-2.5 py-0.5 rounded-full border transition-all ${
            !filterType
              ? 'bg-purple-500/20 text-purple-300 border-purple-500/40'
              : 'bg-slate-900/40 text-slate-400 border-slate-700 hover:border-slate-500'
          }`}
        >
          Alle ({memories.length})
        </button>
        <button
          onClick={() => setFilterType('temporary')}
          className={`text-[10px] px-2.5 py-0.5 rounded-full border transition-all ${
            filterType === 'temporary'
              ? 'bg-cyan-500/20 text-cyan-300 border-cyan-500/40'
              : 'bg-slate-900/40 text-slate-400 border-slate-700 hover:border-slate-500'
          }`}
        >
          Temporär ({memories.filter(m => m.type === 'temporary').length})
        </button>
        <button
          onClick={() => setFilterType('permanent')}
          className={`text-[10px] px-2.5 py-0.5 rounded-full border transition-all ${
            filterType === 'permanent'
              ? 'bg-cyan-500/20 text-cyan-300 border-cyan-500/40'
              : 'bg-slate-900/40 text-slate-400 border-slate-700 hover:border-slate-500'
          }`}
        >
          Permanent ({memories.filter(m => m.type === 'permanent').length})
        </button>
      </div>

      {/* Add Form */}
      {showAdd && (
        <div className="bg-slate-900/60 border border-slate-700/50 rounded-xl p-4 mb-4 space-y-3 animate-in">
          <div>
            <label className="block text-xs font-medium text-slate-400 mb-1.5">Erinnerungstext</label>
            <textarea
              value={newText}
              onChange={e => setNewText(e.target.value)}
              className="input-field text-xs min-h-[60px] resize-none"
              placeholder="z.B. Task X haengt im CI-Build fest..."
              maxLength={300}
            />
            <div className="text-right text-[10px] text-slate-500 mt-0.5">{newText.length}/300</div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-slate-400 mb-1.5">Gedächtnistyp</label>
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => setNewType('temporary')}
                  className={`flex-1 text-xs py-1.5 px-3 rounded-lg border transition-all ${
                    newType === 'temporary'
                      ? 'bg-purple-500/20 text-purple-300 border-purple-500/40 font-semibold'
                      : 'bg-slate-900/40 text-slate-400 border-slate-700 hover:border-slate-600'
                  }`}
                >
                  Temporär (Status)
                </button>
                <button
                  type="button"
                  onClick={() => setNewType('permanent')}
                  className={`flex-1 text-xs py-1.5 px-3 rounded-lg border transition-all ${
                    newType === 'permanent'
                      ? 'bg-purple-500/20 text-purple-300 border-purple-500/40 font-semibold'
                      : 'bg-slate-900/40 text-slate-400 border-slate-700 hover:border-slate-600'
                  }`}
                >
                  Permanent (Richtlinie)
                </button>
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-400 mb-1.5">Priorität</label>
              <select
                value={newPriority}
                onChange={e => setNewPriority(e.target.value)}
                className="input-field text-xs py-1.5"
              >
                <option value="critical">Kritisch</option>
                <option value="high">Hoch</option>
                <option value="medium">Mittel</option>
                <option value="low">Niedrig</option>
              </select>
            </div>
          </div>

          <div className="flex justify-end">
            <button
              onClick={handleAdd}
              disabled={saving || !newText.trim()}
              className="btn-primary text-xs py-1.5 px-4 disabled:opacity-50"
            >
              {saving ? 'Speichern...' : 'Hinzufügen'}
            </button>
          </div>
        </div>
      )}

      {/* Memory List */}
      <div className="space-y-2 max-h-[400px] overflow-y-auto pr-1">
        {filtered.length === 0 ? (
          <div className="text-center text-xs text-slate-500 py-8">
            Keine Erinnerungen vom Typ "{filterType || 'alle'}" vorhanden.
          </div>
        ) : (
          filtered.map(mem => {
            const PIcon = PRIORITY_ICONS[mem.priority] || Info;
            return (
              <div
                key={mem.id}
                className="bg-slate-900/40 border border-slate-800 rounded-lg p-3 group hover:border-slate-600/50 transition-all"
              >
                <div className="flex items-start gap-2">
                  <PIcon className={`w-3.5 h-3.5 mt-0.5 flex-shrink-0 ${
                    mem.priority === 'critical' ? 'text-red-400' :
                    mem.priority === 'high' ? 'text-amber-400' : 'text-slate-400'
                  }`} />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-slate-200 leading-relaxed">{mem.text}</p>
                    <div className="flex items-center gap-2 mt-2">
                      <span className={`text-[9px] px-1.5 py-0.5 rounded border ${PRIORITY_COLORS[mem.priority]}`}>
                        {mem.priority}
                      </span>
                      <span className={`text-[9px] px-1.5 py-0.5 rounded border ${
                        mem.type === 'temporary'
                          ? 'bg-purple-500/20 text-purple-400 border-purple-500/30'
                          : 'bg-slate-800 text-slate-400 border-slate-700'
                      } flex items-center gap-0.5`}>
                        <Tag className="w-2.5 h-2.5" />
                        {mem.type === 'temporary' ? 'Temporär' : 'Permanent'}
                      </span>
                      <span className="text-[9px] text-slate-600 ml-auto">{mem.source}</span>
                    </div>
                  </div>
                  <button
                    onClick={() => handleDelete(mem.id)}
                    className="p-1 text-slate-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all"
                    title="Löschen"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
