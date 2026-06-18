import { FolderOpen, Folder, FileJson, Activity, RefreshCw, AlertTriangle, CheckCircle, Clock } from 'lucide-react';
import { useState, useCallback } from 'react';

interface RunState {
  name: string;
  type: 'main' | 'sub' | 'part';
  status: 'running' | 'completed' | 'failed' | 'pending';
  data: any;
  path: string;
  lastUpdated?: string;
  children?: RunState[];
}

interface RunHierarchyViewProps {
  runStates: RunState[];
  onNodeClick?: (runState: RunState) => void;
  expandedNodes?: Set<string>;
  onToggleNode?: (nodeId: string) => void;
  onSelectFile?: (filePath: string) => void;
}

interface TreeNode {
  id: string;
  name: string;
  type: 'main' | 'sub' | 'part';
  status: 'running' | 'completed' | 'failed' | 'pending';
  path: string;
  lastUpdated?: string;
  children: TreeNode[];
  isExpanded: boolean;
  parentId?: string;
}

export function RunHierarchyView({
  runStates,
  onNodeClick,
  expandedNodes = new Set(),
  onToggleNode,
  onSelectFile
}: RunHierarchyViewProps) {
  const [localExpandedNodes, setLocalExpandedNodes] = useState<Set<string>>(expandedNodes);

  const toggleNode = useCallback((nodeId: string) => {
    if (onToggleNode) {
      onToggleNode(nodeId);
    } else {
      setLocalExpandedNodes(prev => {
        const newSet = new Set(prev);
        if (newSet.has(nodeId)) {
          newSet.delete(nodeId);
        } else {
          newSet.add(nodeId);
        }
        return newSet;
      });
    }
  }, [onToggleNode]);

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'running':
        return <Activity className="w-3 h-3 text-blue-400 animate-pulse" />;
      case 'completed':
        return <CheckCircle className="w-3 h-3 text-green-400" />;
      case 'failed':
        return <AlertTriangle className="w-3 h-3 text-red-400" />;
      case 'pending':
        return <Clock className="w-3 h-3 text-yellow-400" />;
      default:
        return <FileJson className="w-3 h-3 text-slate-400" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'running':
        return 'text-blue-400';
      case 'completed':
        return 'text-green-400';
      case 'failed':
        return 'text-red-400';
      case 'pending':
        return 'text-yellow-400';
      default:
        return 'text-slate-400';
    }
  };

  const getTypeColor = (type: string) => {
    switch (type) {
      case 'main':
        return 'bg-purple-600/20 text-purple-400';
      case 'sub':
        return 'bg-blue-600/20 text-blue-400';
      case 'part':
        return 'bg-slate-600/20 text-slate-400';
      default:
        return 'bg-slate-600/20 text-slate-400';
    }
  };

  const formatTimestamp = (timestamp?: string) => {
    if (!timestamp) return 'N/A';
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMinutes = Math.floor(diffMs / (1000 * 60));

    if (diffMinutes < 1) return 'gerade eben';
    if (diffMinutes < 60) return `vor ${diffMinutes}m`;
    if (diffHours < 24) return `vor ${diffHours}h`;
    return date.toLocaleDateString('de-DE');
  };

  const renderTreeNode = (node: TreeNode, level = 0) => {
    const hasChildren = node.children.length > 0;
    const isExpanded = localExpandedNodes.has(node.id) || expandedNodes.has(node.id);

    return (
      <div key={node.id}>
        <div
          className={`
            flex items-center gap-2 py-2 px-3 rounded-lg cursor-pointer transition-all
            hover:bg-slate-700/50 ${level > 0 ? 'ml-' + (level * 4) : ''}
          `}
          onClick={() => {
            if (hasChildren) {
              toggleNode(node.id);
            }
            if (onNodeClick) {
              onNodeClick(node);
            }
          }}
        >
          {/* Expand/Collapse Icon */}
          {hasChildren && (
            <button
              className="p-0.5 hover:bg-slate-600 rounded transition-colors"
              onClick={(e) => {
                e.stopPropagation();
                toggleNode(node.id);
              }}
            >
              {isExpanded ?
                <FolderOpen className="w-4 h-4 text-slate-400" /> :
                <Folder className="w-4 h-4 text-slate-400" />
              }
            </button>
          )}

          {!hasChildren && <div className="w-4 h-4" />}

          {/* Status Icon */}
          <div className="flex-shrink-0">
            {getStatusIcon(node.status)}
          </div>

          {/* Type Badge */}
          <span className={`text-xs px-2 py-0.5 rounded-full ${getTypeColor(node.type)}`}>
            {node.type.toUpperCase()}
          </span>

          {/* Name */}
          <span className="flex-1 text-sm font-medium text-slate-200">
            {node.name}
          </span>

          {/* Last Updated */}
          <span className="text-xs text-slate-400">
            {formatTimestamp(node.lastUpdated)}
          </span>

          {/* JSON State File Link */}
          <button
            onClick={() => onSelectFile?.(node.path)}
            className="text-xs text-slate-500 hover:text-slate-300 hover:bg-slate-700 px-2 py-1 rounded transition-colors"
            title="JSON-State-File öffnen"
          >
            JSON
          </button>

          {/* Status Text */}
          <span className={`text-xs font-medium ${getStatusColor(node.status)}`}>
            {node.status}
          </span>
        </div>

        {/* Children */}
        {hasChildren && isExpanded && (
          <div className="mt-1">
            {node.children.map(child => renderTreeNode(child, level + 1))}
          </div>
        )}
      </div>
    );
  };

  // Convert flat runStates to hierarchical tree structure
  const buildTree = useCallback(() => {
    const tree: TreeNode[] = [];
    const nodeMap = new Map<string, TreeNode>();

    // First pass: create all nodes
    runStates.forEach(runState => {
      const id = runState.name;
      const parts = runState.name.split('-');

      // Determine type from naming convention
      let type: 'main' | 'sub' | 'part' = 'part';
      if (parts.length >= 3) {
        const prefix = parts[0].toLowerCase();
        if (prefix === 'main') type = 'main';
        else if (prefix === 'sub') type = 'sub';
      } else if (parts.length === 2) {
        type = 'sub';
      }

      nodeMap.set(id, {
        id,
        name: runState.name,
        type,
        status: runState.status,
        path: runState.path,
        lastUpdated: runState.lastUpdated,
        children: [],
        isExpanded: false
      });
    });

    // Second pass: build hierarchy based on naming convention
    runStates.forEach(runState => {
      const node = nodeMap.get(runState.name)!;
      const parts = runState.name.split('-');

      // Build hierarchy: Main-Sub-Part structure
      if (parts.length >= 3) {
        // This is a part, find its sub-run parent
        const subRunName = parts.slice(0, -1).join('-');
        const subNode = nodeMap.get(subRunName);
        if (subNode) {
          subNode.children.push(node);
          node.parentId = subNode.id;
        } else {
          // No sub-run parent found, add to root
          tree.push(node);
        }
      } else if (parts.length === 2) {
        // This is a sub-run, find its main-run parent
        const mainRunName = parts[0];
        const mainNode = nodeMap.get(mainRunName);
        if (mainNode) {
          mainNode.children.push(node);
          node.parentId = mainNode.id;
        } else {
          // No main-run parent found, add to root
          tree.push(node);
        }
      } else {
        // This is a main-run, add to root
        tree.push(node);
      }
    });

    // Sort nodes: main first, then sub, then part
    const sortNodes = (nodes: TreeNode[]) => {
      return nodes.sort((a, b) => {
        const typeOrder = { main: 0, sub: 1, part: 2 };
        if (typeOrder[a.type] !== typeOrder[b.type]) {
          return typeOrder[a.type] - typeOrder[b.type];
        }
        return a.name.localeCompare(b.name);
      });
    };

    // Apply sorting to all levels
    const recursiveSort = (node: TreeNode): TreeNode => {
      const sortedChildren = sortNodes(node.children);
      return {
        ...node,
        children: sortedChildren.map(recursiveSort)
      };
    };

    return sortNodes(tree).map(recursiveSort);
  }, [runStates]);

  const tree = buildTree();

  return (
    <div className="space-y-2">
      {tree.map(node => renderTreeNode(node))}

      {tree.length === 0 && (
        <div className="text-center py-8 text-slate-500">
          Keine Run-States gefunden
        </div>
      )}
    </div>
  );
}

// Alternative component for flat view
interface RunFlatViewProps {
  runStates: RunState[];
  onNodeClick?: (runState: RunState) => void;
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
              runState.type === 'sub' ? 'bg-blue-600/20 text-blue-400' :
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