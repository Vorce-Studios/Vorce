// ── Quota / Registry Types ──
export interface ProviderModel {
  name: string;
  estimated_cost_per_call_usd: number;
}

export interface ProviderUsage {
  calls: number;
  estimated_cost_usd: number;
  source?: string;
  last_synced_at?: string;
  [key: string]: unknown;
}

export interface Provider {
  enabled: boolean;
  purpose: string[];
  command?: string;
  cli_args?: string[];
  stats_format?: string;
  auth_env_var?: string | null;
  models?: Record<string, ProviderModel>;
  daily_limit: number;
  daily_budget_usd?: number;
  estimated_cost_per_call_usd?: number;
  usage_today: ProviderUsage;
}

export interface RoutingRules {
  [taskType: string]: string[];
}

export interface QuotaRegistry {
  schema_version: number;
  daily_reset_hour_utc: number;
  last_reset_date: string;
  providers: Record<string, Provider>;
  routing_rules: RoutingRules;
}

// ── Active Sessions Types ──
export interface ActiveDelegation {
  issue_number: number;
  issue_title: string;
  jules_session_id: string;
  jules_state: string;
  pr_url: string | null;
  delegated_at: string;
  last_checked_at: string;
  retry_count: number;
}

export interface ReviewQueueItem {
  issue_number: number;
  pr_url: string;
  pr_number: number;
  review_status: string;
}

export interface CompletedItem {
  issue_number: number;
  result: string;
  completed_at: string;
}

export interface DecisionPending {
  topic: string;
  context: string;
  created_at: string;
}

export interface ActiveSessions {
  schema_version: number;
  session_id: string;
  started_at: string;
  last_heartbeat: string;
  last_planning_at: string;
  last_monitoring_at: string;
  active_delegations: ActiveDelegation[];
  review_queue: ReviewQueueItem[];
  autopilot_created_issues: unknown[];
  completed_this_session: CompletedItem[];
  decisions_pending?: DecisionPending[];
}

// ── GitHub Issues Types ──
export interface IssueLabel {
  id: string;
  name: string;
  description: string;
  color: string;
}

export interface GitHubIssue {
  assignees: string[];
  body: string;
  createdAt: string;
  labels: IssueLabel[];
  milestone: string | null;
  number: number;
  state: string;
  title: string;
  updatedAt: string;
  url: string;
}

// ── Pull Requests Types ──
export interface StatusCheck {
  __typename: string;
  completedAt?: string;
  conclusion?: string;
  detailsUrl?: string;
  name?: string;
  startedAt?: string;
  status?: string;
  workflowName?: string;
  context?: string;
  state?: string;
  targetUrl?: string;
}

export interface PullRequest {
  baseRefName: string;
  headRefName: string;
  mergeable: string;
  number: number;
  state: string;
  statusCheckRollup: StatusCheck[];
  title: string;
  updatedAt: string;
  url: string;
}

// ── Autopilot Config Types ──
export interface AutopilotConfig {
  repository: string;
  wake_intervals: {
    planning_minutes: number;
    monitoring_minutes: number;
  };
  jules: {
    max_daily_sessions: number;
    max_concurrent_sessions: number;
    auto_approve_plans: boolean;
    auto_retry_feedback_max: number;
    auto_merge_approved_prs?: boolean;
    monitoring_refill_enabled?: boolean;
    monitoring_refill_buffer_size?: number;
  };
  gemini_worktree_path: string;
  issue_filters: {
    include_labels: string[];
    exclude_labels: string[];
    autopilot_label: string;
  };
  max_issues_per_planning_cycle: number;
  dual_ceo: DualCeoConfig;
  prompts?: {
    planning_jules_sync?: string;
    planning_pr_sync?: string;
    planning_analysis?: string;
    planning_proposal?: string;
    planning_synthesis?: string;
    monitor_sessions?: string;
    monitor_prs?: string;
    monitor_conflicts?: string;
    monitoring_synthesis?: string;
    audit_consistency?: string;
    audit_performance?: string;
    audit_synthesis?: string;
    audit_prompt?: string;
    monitoring_prompt?: string;
  };
}

// ── Dual-CEO Types ──
export interface DualCeoConfig {
  enabled: boolean;
  ceo_alpha_chain: string[];
  ceo_beta_chain: string[];
  max_deliberation_rounds: number;
  deliberation_tasks: string[];
  fallback_to_single: boolean;
  log_deliberations: boolean;
}

// ── Memory System Types ──
export interface MemoryEntry {
  id: string;
  text: string;
  type: 'permanent' | 'temporary';
  priority: 'critical' | 'high' | 'medium' | 'low';
  created_at: string;
  source: string;
}

export interface MemoryStore {
  schema_version: number;
  memories: MemoryEntry[];
}

export type TabId = 'dashboard' | 'workstreams' | 'reporting' | 'settings';
