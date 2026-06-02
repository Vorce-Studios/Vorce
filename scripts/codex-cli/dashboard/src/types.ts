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
  agent_type?: string;
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
  id?: string;
  topic: string;
  context: string;
  created_at: string;
  status?: string;
  owner?: 'beta_ceo' | 'alpha_ceo' | 'user' | 'system';
  source?: 'audit' | 'monitoring' | 'planning' | string;
  process_stage?: 'beta_remediation' | 'alpha_review' | 'alpha_remediation_planned' | 'user_decision' | string;
  escalation_level?: 'none' | 'alpha' | 'user' | string;
  remediation_command?: string;
  remediation_result?: string;
  remediation_attempted_at?: string;
  alpha_attempted_at?: string;
  alpha_attempts?: number;
  alpha_response?: string;
  user_response?: string;
  user_escalation_reason?: string;
  resolution_attempted_at?: string;
}

export interface SchedulerSnapshot {
  planning_interval_minutes: number;
  monitoring_interval_minutes: number;
  last_planning_at?: string;
  last_monitoring_at?: string;
  next_planning_at?: string;
  next_monitoring_at?: string;
  next_planning_in_seconds?: number;
  next_monitoring_in_seconds?: number;
}

export interface RunControl {
  cancel_next_planning?: boolean;
  cancel_next_monitoring?: boolean;
  next_planning_note?: string;
  next_monitoring_note?: string;
  updated_at?: string;
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
  deliberation_log?: any[];
  scheduler?: SchedulerSnapshot;
  run_control?: RunControl;
  processing_queue?: number[];
  working_sessions?: any[];
}

export interface AuditResult {
  session_id?: string;
  response?: string;
  parsed?: {
    issues_found?: boolean;
    action?: 'remediate' | 'escalate' | 'none' | string;
    remediation_command?: string;
    dashboard_escalation?: string;
    [key: string]: unknown;
  } | null;
  stats?: any;
  updated_at?: string;
  error?: string;
}

// ── GitHub Project Types ──
export interface ProjectItem {
  id: string;
  status: string;
  jules_session_status?: string;
  pr_checks_status?: string;
  review_status?: string;
  [key: string]: any;
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
  repo?: string;
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
  isDraft?: boolean;
  reviewDecision?: string;
  repo?: string;
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
  };
  gemini_worktree_path: string;
  issue_filters: {
    include_labels: string[];
    exclude_labels: string[];
    autopilot_label: string;
  };
  max_issues_per_planning_cycle: number;
  dual_ceo: DualCeoConfig;
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
