import { useCallback, useState } from 'react';
import { LayoutDashboard, Activity, Settings, RefreshCw, Zap, BarChart3, Menu } from 'lucide-react';
import { useData, useAutoRefresh } from './hooks';
import { useWebSocket } from './hooks/useWebSocket';

// Pages
import DashboardPage from './pages/DashboardPage';
import WorkstreamsPage from './pages/WorkstreamsPage';
import SettingsPage from './pages/SettingsPage';
import ManagerReportingPage from './pages/ManagerReportingPage';

// Types
import type { TabId, AutopilotConfig, QuotaRegistry, ActiveSessions, GitHubIssue, PullRequest, MemoryStore } from './types';

// Defaults
const defaultAutopilotConfig: AutopilotConfig = {
  repository: 'Vorce-Studios/Vorce',
  wake_intervals: {
    planning_minutes: 120,
    check_and_doing_minutes: 15,
    audit_minutes: 60,
    optimizer_minutes: 720,
    memory_optimization_minutes: 60,
  },
  jules: {
    max_daily_sessions: 100,
    max_concurrent_sessions: 15,
    auto_approve_plans: true,
    auto_retry_feedback_max: 3
  },
  gemini_worktree_path: '../VjMapper-gemini',
  issue_filters: {
    include_labels: ['jules-task', 'bug', 'priority: critical'],
    exclude_labels: ['wontfix', 'duplicate', 'on-hold', 'status: in-progress', 'status: needs-review', 'status: needs-testing', 'status: blocked', 'status: ready-to-merge'],
    autopilot_label: 'autopilot-created'
  },
  max_issues_per_planning_cycle: 5,
  dual_ceo: {
    enabled: true,
    ceo_chain: ['codex_orchestrator:planning', 'claude_code:balanced'],
    qa_manager_chain: ['gemini_cli:balanced', 'kiro_cli:default'],
    max_deliberation_rounds: 3,
    deliberation_tasks: ['planning', 'complex_review'],
    fallback_to_single: true,
    log_deliberations: true
  }
};

const defaultQuotaRegistry: QuotaRegistry = {
  schema_version: 1,
  daily_reset_hour_utc: 0,
  last_reset_date: '',
  providers: {},
  routing_rules: {}
};

const defaultActiveSessions: ActiveSessions = {
  schema_version: 1,
  session_id: 'N/A',
  started_at: '',
  last_heartbeat: '',
  active_delegations: [],
  review_queue: [],
  autopilot_created_issues: [],
  completed_this_session: [],
  deliberation_log: []
};

export default function App() {
  const [activeTab, setActiveTab] = useState<TabId>('dashboard');
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);

  // Fetch data hooks
  const { data: config, loading: configLoading, refetch: refetchConfig } = useData<AutopilotConfig>('/autopilot-config.json', defaultAutopilotConfig);
  const { data: registry, loading: registryLoading, refetch: refetchRegistry } = useData<QuotaRegistry>('/registry.json', defaultQuotaRegistry);
  const { data: sessions, loading: sessionsLoading, refetch: refetchSessions } = useData<ActiveSessions>('/active-sessions.json', defaultActiveSessions);
  const { data: issues, loading: issuesLoading, refetch: refetchIssues } = useData<GitHubIssue[]>('/github-issues.json', []);
  const { data: pullRequests, loading: prLoading, refetch: refetchPRs } = useData<PullRequest[]>('/pull-requests.json', []);
  const { data: projectItems, refetch: refetchProjectItems } = useData<any>('/project-items.json', { items: [] });
  const { data: julesSessions, refetch: refetchJulesSessions } = useData<any[]>('/jules-sessions.json', []);
  const { data: memoryStore, refetch: refetchMemory } = useData<MemoryStore>('/memories.json', { schema_version: 1, memories: [] });
  const { data: history, loading: historyLoading, refetch: refetchHistory } = useData<any[]>('/data.json', []);
  const { data: auditResult, refetch: refetchAuditResult } = useData<any>('/audit-result.json', null);
  const { data: liveLog, refetch: refetchLiveLog } = useData<{ content?: string }>('/live-log.json', {});

  const refetchAll = useCallback(() => {
    refetchConfig();
    refetchRegistry();
    refetchSessions();
    refetchIssues();
    refetchPRs();
    refetchProjectItems();
    refetchJulesSessions();
    refetchMemory();
    refetchHistory();
    refetchAuditResult();
    refetchLiveLog();
  }, [refetchConfig, refetchRegistry, refetchSessions, refetchIssues, refetchPRs, refetchProjectItems, refetchJulesSessions, refetchMemory, refetchHistory, refetchAuditResult, refetchLiveLog]);

  // WebSocket pushes trigger immediate refreshes; polling remains as a fallback.
  useWebSocket({ onMessage: refetchAll });
  useAutoRefresh(refetchAll, 30000);

  const isGlobalLoading = configLoading && registryLoading && sessionsLoading && issuesLoading && prLoading && historyLoading;

    const renderActivePage = () => {
      switch (activeTab) {
        case 'dashboard':
          return <DashboardPage registry={registry} sessions={sessions} pullRequests={pullRequests} issues={issues} julesSessions={julesSessions} auditResult={auditResult} liveLog={liveLog?.content || ''} />;
        case 'workstreams':
          return <WorkstreamsPage issues={issues} sessions={sessions} pullRequests={pullRequests} julesSessions={julesSessions} projectItems={projectItems?.items || []} />;
        case 'reporting':
        return (
          <ManagerReportingPage
            registry={registry}
            sessions={sessions}
            issues={issues}
            pullRequests={pullRequests}
            history={history}
          />
        );
      case 'settings':
        return (
          <SettingsPage
            config={config}
            registry={registry}
            memoryStore={memoryStore}
            onSave={refetchAll}
            onMemoryRefresh={refetchMemory}
          />
        );
      default:
        return <div className="text-slate-400">Seite nicht gefunden.</div>;
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      {/* Top Header Navigation */}
      <header className="border-b border-slate-800 bg-slate-900/60 backdrop-blur-md sticky top-0 z-50">
        <div className="w-full px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setIsSidebarOpen(!isSidebarOpen)}
              className="p-2 mr-2 text-slate-400 hover:text-slate-200 hover:bg-slate-800 rounded-lg transition-all duration-200"
              title="Sidebar umschalten"
            >
              <Menu className="w-5 h-5" />
            </button>
            <div className="w-9 h-9 rounded-lg bg-gradient-to-br from-purple-600 to-cyan-500 flex items-center justify-center shadow-lg shadow-purple-500/20">
              <Zap className="w-5 h-5 text-white" />
            </div>
            <div>
              <h1 className="text-md font-bold text-white tracking-wide">Vorce Autopilot</h1>
              <p className="text-[10px] text-slate-400 font-medium">System Dashboard</p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={refetchAll}
              disabled={isGlobalLoading}
              className="p-2 text-slate-400 hover:text-slate-200 hover:bg-slate-800 rounded-lg transition-all duration-200"
              title="Daten aktualisieren"
            >
              <RefreshCw className={`w-4 h-4 ${isGlobalLoading ? 'animate-spin' : ''}`} />
            </button>
          </div>
        </div>
      </header>

      {/* Main Container */}
      <main className="flex-1 w-full px-4 sm:px-6 lg:px-8 py-6 flex flex-col md:flex-row gap-6">
        {/* Navigation Sidebar */}
        <aside className={`md:w-64 flex-shrink-0 transition-all duration-300 ${isSidebarOpen ? 'block' : 'hidden'}`}>
          <nav className="space-y-1.5 sticky top-22">
            <button
              onClick={() => setActiveTab('dashboard')}
              className={activeTab === 'dashboard' ? 'tab-btn-active w-full' : 'tab-btn-inactive w-full'}
            >
              <LayoutDashboard className="w-4 h-4" />
              <span>Dashboard Overview</span>
            </button>
            <button
              onClick={() => setActiveTab('workstreams')}
              className={activeTab === 'workstreams' ? 'tab-btn-active w-full' : 'tab-btn-inactive w-full'}
            >
              <Activity className="w-4 h-4 text-emerald-400" />
              <span>Smart Workstreams</span>
              {(sessions.decisions_pending && sessions.decisions_pending.length > 0) && (
                <span className="ml-auto badge bg-rose-500/20 text-rose-400 px-1.5 py-0.5 text-[10px]">
                  {sessions.decisions_pending.length} ALERTS
                </span>
              )}
            </button>
            <button
              onClick={() => setActiveTab('reporting')}
              className={activeTab === 'reporting' ? 'tab-btn-active w-full' : 'tab-btn-inactive w-full'}
            >
              <BarChart3 className="w-4 h-4" />
              <span>Manager Reporting</span>
            </button>
            <div className="h-px bg-slate-800 my-4" />
            <button
              onClick={() => setActiveTab('settings')}
              className={activeTab === 'settings' ? 'tab-btn-active w-full' : 'tab-btn-inactive w-full'}
            >
              <Settings className="w-4 h-4" />
              <span>System-Settings</span>
            </button>
          </nav>
        </aside>

        {/* Dynamic Page Content */}
        <section className="flex-1 min-w-0">
          {renderActivePage()}
        </section>
      </main>

      {/* Footer */}
      <footer className="border-t border-slate-900 bg-slate-950 py-4 mt-auto">
        <div className="max-w-7xl mx-auto px-4 text-center text-xs text-slate-600">
          Vorce-Autopilot Dashboard &bull; Build with Vite & React &bull; 2026
        </div>
      </footer>
    </div>
  );
}
