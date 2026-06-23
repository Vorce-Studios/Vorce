import { Activity, AlertTriangle, CheckCircle, Clock, FileJson, Folder, FolderOpen } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { RunHierarchyData, RunHierarchyMain, RunHierarchyPart, RunHierarchySub } from '../types';

type NodeKind = 'main' | 'sub' | 'part';

type HierarchyNode =
  | { kind: 'main'; id: string; main: RunHierarchyMain }
  | { kind: 'sub'; id: string; main: RunHierarchyMain; sub: RunHierarchySub }
  | { kind: 'part'; id: string; main: RunHierarchyMain; sub: RunHierarchySub; part: RunHierarchyPart };

interface RunHierarchyViewProps {
  runHierarchy?: RunHierarchyData | null;
  onNodeClick?: (node: HierarchyNode) => void;
  expandedNodes?: Set<string>;
  onToggleNode?: (nodeId: string) => void;
  onSelectFile?: (filePath: string) => void;
}

function statusIcon(status: string) {
  switch (status) {
    case 'running':
      return <Activity className="w-3 h-3 text-blue-400 animate-pulse" />;
    case 'completed':
    case 'reused':
      return <CheckCircle className="w-3 h-3 text-emerald-400" />;
    case 'failed':
      return <AlertTriangle className="w-3 h-3 text-red-400" />;
    case 'waiting_provider':
      return <Clock className="w-3 h-3 text-amber-400" />;
    default:
      return <FileJson className="w-3 h-3 text-slate-400" />;
  }
}

function statusColor(status: string) {
  switch (status) {
    case 'running':
      return 'text-blue-300';
    case 'completed':
    case 'reused':
      return 'text-emerald-300';
    case 'failed':
      return 'text-red-300';
    case 'waiting_provider':
      return 'text-amber-300';
    case 'skipped':
      return 'text-slate-400';
    default:
      return 'text-slate-500';
  }
}

function badgeClass(kind: NodeKind) {
  switch (kind) {
    case 'main':
      return 'bg-purple-600/20 text-purple-300 border-purple-500/20';
    case 'sub':
      return 'bg-cyan-600/15 text-cyan-300 border-cyan-500/20';
    default:
      return 'bg-slate-700/40 text-slate-300 border-slate-700';
  }
}

function formatTimestamp(timestamp?: string | null) {
  if (!timestamp) return 'N/A';
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return 'N/A';
  return date.toLocaleString('de-DE', { dateStyle: 'short', timeStyle: 'short' });
}

function nodeLabel(label?: string) {
  return label || '';
}

export function RunHierarchyView({
  runHierarchy,
  onNodeClick,
  expandedNodes = new Set(),
  onToggleNode,
  onSelectFile
}: RunHierarchyViewProps) {
  const [localExpandedNodes, setLocalExpandedNodes] = useState<Set<string>>(new Set());

  useEffect(() => {
    const nextExpanded = new Set<string>();
    for (const main of runHierarchy?.main_runs || []) {
      nextExpanded.add(main.name);
      for (const sub of main.sub_runs) {
        if (sub.router_active_last_run || sub.activation_reason === 'activated_in_last_run') {
          nextExpanded.add(`${main.name}::${sub.name}`);
        }
      }
    }
    setLocalExpandedNodes(nextExpanded);
  }, [runHierarchy]);

  const toggleNode = (nodeId: string) => {
    if (onToggleNode) {
      onToggleNode(nodeId);
      return;
    }

    setLocalExpandedNodes(prev => {
      const next = new Set(prev);
      if (next.has(nodeId)) {
        next.delete(nodeId);
      } else {
        next.add(nodeId);
      }
      return next;
    });
  };

  const tree = runHierarchy?.main_runs || [];
  const legacyCount = runHierarchy?.legacy_orphan_states?.length || 0;

  const isExpanded = (nodeId: string, forceOpen = false) =>
    forceOpen || localExpandedNodes.has(nodeId) || expandedNodes.has(nodeId);

  const renderPart = (main: RunHierarchyMain, sub: RunHierarchySub, part: RunHierarchyPart) => {
    const id = `${main.name}::${sub.name}::${part.name}`;
    const clickable = Boolean(part.latest_state_path);

    return (
      <div
        key={id}
        className="flex items-center gap-2 py-2 px-3 rounded-lg hover:bg-slate-700/35 transition-colors"
        style={{ marginLeft: 44 }}
      >
        <div className="w-4 h-4 flex-shrink-0" />
        <div className="flex-shrink-0">{statusIcon(part.runtime_status)}</div>
        <span className={`text-xs px-2 py-0.5 rounded-full border ${badgeClass('part')}`}>
          PART
        </span>
        <div className="min-w-0 flex-1">
          <div className="text-sm font-medium text-slate-100 truncate">{part.name}</div>
          <div className="text-[11px] text-slate-400 truncate">
            {nodeLabel(part.label)} {part.activation_reason ? `• ${part.activation_reason}` : ''}
            {part.inactive_reason ? ` • ${part.inactive_reason}` : ''}
          </div>
        </div>
        <span className={`text-xs font-medium ${statusColor(part.runtime_status)}`}>
          {part.runtime_status}
        </span>
        <span className="text-xs text-slate-400">{formatTimestamp(part.timestamp || null)}</span>
        {clickable && (
          <button
            type="button"
            onClick={() => onSelectFile?.(part.latest_state_path || '')}
            className="text-xs text-slate-400 hover:text-slate-200 hover:bg-slate-700 px-2 py-1 rounded transition-colors"
            title="JSON-State öffnen"
          >
            JSON
          </button>
        )}
      </div>
    );
  };

  const renderSub = (main: RunHierarchyMain, sub: RunHierarchySub) => {
    const id = `${main.name}::${sub.name}`;
    const open = isExpanded(id);
    const activeCount = sub.part_runs.filter(part => part.runtime_status !== 'skipped').length;
    const statusText =
      !sub.configured_enabled ? 'config-disabled' :
      sub.runtime_status === 'skipped' ? 'not-run' :
      sub.router_active_last_run ? 'aktiv' : 'inaktiv';

    return (
      <div key={id}>
        <div
          className="flex items-center gap-2 py-2 px-3 rounded-lg hover:bg-slate-700/35 transition-colors cursor-pointer"
          style={{ marginLeft: 24 }}
          onClick={() => {
            toggleNode(id);
            onNodeClick?.({ kind: 'sub', id, main, sub });
          }}
        >
          <button
            type="button"
            className="p-0.5 hover:bg-slate-600 rounded transition-colors"
            onClick={(event) => {
              event.stopPropagation();
              toggleNode(id);
            }}
          >
            {open ? <FolderOpen className="w-4 h-4 text-slate-400" /> : <Folder className="w-4 h-4 text-slate-400" />}
          </button>
          <div className="flex-shrink-0">{statusIcon(sub.runtime_status)}</div>
          <span className={`text-xs px-2 py-0.5 rounded-full border ${badgeClass('sub')}`}>
            SUB
          </span>
          <div className="min-w-0 flex-1">
            <div className="text-sm font-medium text-slate-100 truncate">{sub.name}</div>
            <div className="text-[11px] text-slate-400 truncate">
              {nodeLabel(sub.label)} • {statusText} • {activeCount}/{sub.part_runs.length} PARTS
              {sub.inactive_reason ? ` • ${sub.inactive_reason}` : ''}
            </div>
          </div>
          <span className={`text-xs font-medium ${statusColor(sub.runtime_status)}`}>
            {sub.runtime_status}
          </span>
          <span className="text-xs text-slate-400">
            {sub.router_active_last_run ? 'letzter Lauf aktiv' : 'letzter Lauf inaktiv'}
          </span>
          {sub.latest_state_path && (
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                onSelectFile?.(sub.latest_state_path || '');
              }}
              className="text-xs text-slate-400 hover:text-slate-200 hover:bg-slate-700 px-2 py-1 rounded transition-colors"
              title="JSON-State öffnen"
            >
              JSON
            </button>
          )}
        </div>
        {open && sub.part_runs.length > 0 && (
          <div className="mt-1">
            {sub.part_runs.map(part => renderPart(main, sub, part))}
          </div>
        )}
      </div>
    );
  };

  const renderMain = (main: RunHierarchyMain) => {
    const id = main.name;
    const open = isExpanded(id);

    return (
      <div key={id} className="rounded-xl border border-slate-800 bg-slate-900/40 overflow-hidden">
        <div
          className="flex items-center gap-2 py-3 px-3 cursor-pointer hover:bg-slate-800/50 transition-colors"
          onClick={() => {
            toggleNode(id);
            onNodeClick?.({ kind: 'main', id, main });
          }}
        >
          <button
            type="button"
            className="p-0.5 hover:bg-slate-700 rounded transition-colors"
            onClick={(event) => {
              event.stopPropagation();
              toggleNode(id);
            }}
          >
            {open ? <FolderOpen className="w-5 h-5 text-purple-300" /> : <Folder className="w-5 h-5 text-purple-300" />}
          </button>
          <div className="flex-shrink-0">{statusIcon(main.latest_state_status || 'pending')}</div>
          <span className={`text-xs px-2 py-0.5 rounded-full border ${badgeClass('main')}`}>
            MAIN
          </span>
          <div className="min-w-0 flex-1">
            <div className="text-sm font-semibold text-slate-100 truncate">{main.name}</div>
            <div className="text-[11px] text-slate-400 truncate">
              {main.label} • Router: {main.router_key} • {main.active_sub_runs_last_run}/{main.configured_sub_runs} aktive SUBS
            </div>
          </div>
          <span className={`text-xs font-medium ${statusColor(main.latest_state_status || 'not_started')}`}>
            {main.latest_state_status || 'not_started'}
          </span>
          <span className="text-xs text-slate-400">
            {formatTimestamp(main.last_run_timestamp || null)}
          </span>
          {main.latest_state_path && (
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                onSelectFile?.(main.latest_state_path || '');
              }}
              className="text-xs text-slate-400 hover:text-slate-200 hover:bg-slate-700 px-2 py-1 rounded transition-colors"
              title="JSON-State öffnen"
            >
              JSON
            </button>
          )}
        </div>

        {open && (
          <div className="pb-2">
            {main.sub_runs.map(sub => renderSub(main, sub))}
          </div>
        )}
      </div>
    );
  };

  if (!tree.length) {
    return <div className="text-center py-8 text-slate-500">Keine Run-Hierarchie gefunden</div>;
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between text-xs text-slate-500 px-1">
        <span>{tree.length} MAIN-RUNs</span>
        <span>{legacyCount > 0 ? `${legacyCount} Legacy-State(s)` : 'Keine Legacy-States'}</span>
      </div>
      {tree.map(main => renderMain(main))}
    </div>
  );
}

interface RunFlatViewProps {
  runStates: Array<{
    name: string;
    type: 'main' | 'sub' | 'part';
    status: 'running' | 'completed' | 'failed' | 'pending';
  }>;
  onNodeClick?: (runState: { name: string; type: 'main' | 'sub' | 'part'; status: string }) => void;
}

export function RunFlatView({ runStates, onNodeClick }: RunFlatViewProps) {
  return (
    <div className="space-y-2">
      {runStates.map((runState) => (
        <div
          key={runState.name}
          className="flex items-center gap-3 p-3 rounded-lg bg-slate-800/50 hover:bg-slate-700/50 cursor-pointer transition-colors"
          onClick={() => onNodeClick?.(runState)}
        >
          <FileJson className="w-4 h-4 text-slate-400" />
          <span className="text-sm font-medium text-slate-200">{runState.name}</span>
          <div className="flex gap-2 ml-auto">
            <span className={`text-xs px-2 py-1 rounded-full ${
              runState.type === 'main' ? 'bg-purple-600/20 text-purple-400' :
              runState.type === 'sub' ? 'bg-cyan-600/20 text-cyan-400' :
              'bg-slate-600/20 text-slate-400'
            }`}>
              {runState.type.toUpperCase()}
            </span>
            <span className={`text-xs px-2 py-1 rounded-full ${
              runState.status === 'running' ? 'bg-blue-600/20 text-blue-400' :
              runState.status === 'completed' ? 'bg-green-600/20 text-green-400' :
              runState.status === 'failed' ? 'bg-red-600/20 text-red-400' :
              'bg-yellow-600/20 text-yellow-400'
            }`}>
              {runState.status}
            </span>
          </div>
        </div>
      ))}

      {runStates.length === 0 && (
        <div className="text-center py-8 text-slate-500">
          Keine Run-States gefunden
        </div>
      )}
    </div>
  );
}
