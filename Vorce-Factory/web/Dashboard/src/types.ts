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
  review_provider?: string;
  pr_updated_at?: string;
  reviewed_pr_updated_at?: string;
  reviewed_at?: string;
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
  status?: 'pending' | 'closed' | 'ignored';
  closed_by?: string;
  closed_at?: string;
  user_comment?: string;
  memory_id?: string;
}

export interface MainRunRuntime {
  name: string;
  label: string;
  routerKey: string;
  intervalKey: string;
  interval_minutes: number;
  last_run_at?: string | null;
  next_run_at?: string;
  next_run_in_seconds?: number;
  status: string;
  summary?: string;
  latest_state?: unknown;
  sub_runs: unknown[];
  control?: {
    cancel_next?: boolean;
    note?: string;
    updated_at?: string;
    skipped_at?: string;
  };
}

export interface ActiveSessions {
  schema_version: number;
  session_id: string;
  started_at: string;
  last_heartbeat: string;
  active_delegations: ActiveDelegation[];
  working_queue?: unknown[];
  working_sessions?: unknown[];
  review_queue: ReviewQueueItem[];
  autopilot_created_issues: unknown[];
  completed_this_session: CompletedItem[];
  decisions_pending?: DecisionPending[];
  deliberation_log?: DeliberationLogEntry[];
  run_control?: Record<string, unknown>;
  optimizer_queue?: OptimizerProposal[];
  last_optimizer_analysis_at?: string;
  optimizer_last_run?: OptimizerRun;
  main_runs?: MainRunRuntime[];
  run_states?: unknown[];
  run_hierarchy?: RunHierarchyData | null;
}

export interface RunHierarchyPart {
  id: string;
  name: string;
  label?: string;
  script: string;
  parent_main_name: string;
  parent_sub_name: string;
  configured_enabled: boolean;
  runtime_status: string;
  activation_reason?: string | null;
  inactive_reason?: string | null;
  latest_state_path?: string | null;
  timestamp?: string | null;
}

export interface RunHierarchySub {
  id: string;
  name: string;
  label?: string;
  script: string;
  parent_main_name: string;
  configured_enabled: boolean;
  runtime_status: string;
  activation_reason?: string | null;
  inactive_reason?: string | null;
  router_active_last_run?: boolean;
  latest_state_path?: string | null;
  part_runs: RunHierarchyPart[];
}

export interface RunHierarchyRouterDecisionConfiguredSubRun {
  id: string;
  name: string;
  script: string;
  configured_enabled: boolean;
  active: boolean;
  reason: 'active_by_router' | 'disabled_in_config' | 'skipped_by_router_condition';
}

export interface RunHierarchyRouterDecisionActiveSubRun {
  name: string;
  active: true;
}

export interface RunHierarchyRouterDecisionInactiveSubRun {
  id: string;
  name: string;
  script: string;
  active: false;
  reason: 'disabled_in_config' | 'skipped_by_router_condition';
}

export interface RunHierarchyRouterDecision {
  configured_sub_runs: RunHierarchyRouterDecisionConfiguredSubRun[];
  active_sub_runs: RunHierarchyRouterDecisionActiveSubRun[];
  inactive_sub_runs: RunHierarchyRouterDecisionInactiveSubRun[];
  router_key: string;
  decision_timestamp?: string | null;
}

export interface RunHierarchyMain {
  name: string;
  label: string;
  router_key: string;
  interval_key: string;
  configured_sub_runs: number;
  active_sub_runs_last_run: number;
  latest_state_path?: string | null;
  latest_state_status?: string;
  last_run_timestamp?: string | null;
  router_decision?: RunHierarchyRouterDecision;
  sub_runs: RunHierarchySub[];
}

export interface RunHierarchyData {
  schema_version: number;
  generated_at: string;
  main_runs: RunHierarchyMain[];
  legacy_orphan_states?: Array<{
    source_file: string;
    type?: string;
    name?: string;
    timestamp?: string | null;
  }>;
}

export interface RecentRunSummary {
  run_id: string;
  main_run: string;
  status: string;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number | null;
  sub_runs: {
    completed: number;
    failed: number;
    skipped: number;
    reused: number;
  };
  part_runs: {
    completed: number;
    failed: number;
    skipped: number;
    reused: number;
  };
  provider_attempts: number;
  fallbacks: number;
  estimated_cost_usd: number;
  input_tokens: number;
  output_tokens: number;
  resume_count: number;
  no_work: number;
  result_summary: string;
  primary_error: string | null;
}

export interface RunWindowStats {
  runs_started?: number;
  runs_completed?: number;
  runs_failed?: number;
  runs_waiting_provider?: number;
  success_rate?: number;
  avg_duration_ms?: number;
  p95_duration_ms?: number;
  sub_runs_completed?: number;
  sub_runs_failed?: number;
  sub_runs_skipped?: number;
  sub_runs_reused?: number;
  part_runs_completed?: number;
  part_runs_failed?: number;
  part_runs_skipped?: number;
  part_runs_reused?: number;
  provider_attempts?: number;
  fallbacks?: number;
  timeout_errors?: number;
  rate_limit_errors?: number;
  auth_errors?: number;
  estimated_cost_usd?: number;
  input_tokens?: number;
  output_tokens?: number;
  resume_count?: number;
  no_work?: number;
}

export interface RunSummary {
  generated_at: string;
  recent_runs: RecentRunSummary[];
  stats_24h: RunWindowStats;
  stats_7d: RunWindowStats;
}

// ── GitHub Project Types ──
export interface ProjectItem {
  id: string;
  status: string;
  jules_session_status?: string;
  pr_checks_status?: string;
  review_status?: string;
  [key: string]: unknown;
}

export interface ProjectItemsResponse {
  items: ProjectItem[];
}

export interface JulesSession {
  repo?: string;
  state?: string;
  [key: string]: unknown;
}

export interface HistoryEntry {
  [key: string]: unknown;
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
export type RouterMode = 'always' | 'automatic' | 'manual_only';

export type RouterCondition =
  | 'always'
  | 'pipeline_below_limit'
  | 'has_untriaged_issues'
  | 'has_approved_proposals'
  | 'has_active_jules_delegations'
  | 'has_active_local_agent_sessions'
  | 'has_open_prs_requiring_review'
  | 'jules_capacity_available'
  | 'housekeeping_due'
  | 'has_new_audit_inputs'
  | 'has_open_alerts'
  | 'optimizer_has_sufficient_samples'
  | 'optimizer_has_findings'
  | 'optimizer_has_approved_changes'
  | 'optimizer_has_changes_to_evaluate'
  | 'memory_maintenance_due'
  | 'memory_has_candidates'
  | 'master_issue_context_changed';

export interface RouterConditionSettings {
  interval_minutes?: number;
  max_interval_minutes?: number;
  minimum_samples?: number;
}

export interface RouterRule {
  id: string;
  name: string;
  script: string;
  enabled: boolean;
  mode: RouterMode;
  condition: RouterCondition;
  condition_settings: RouterConditionSettings;
  dashboard_editable: boolean;
}

export interface RouterRules {
  Planning: RouterRule[];
  CheckAndDoing: RouterRule[];
  Audit: RouterRule[];
  Optimizer: RouterRule[];
  MemoryOptimization: RouterRule[];
}

export interface AutopilotConfig {
  repository: string;
  wake_intervals: {
    planning_minutes: number;
    check_and_doing_minutes: number;
    audit_minutes: number;
    optimizer_minutes: number;
    memory_optimization_minutes: number;
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
  working_sessions?: WorkingSessionsConfig;
  dual_ceo: DualCeoConfig;
  router_rules?: RouterRules;
  run_settings?: RunSettings;
  prompts?: {
    planning_analysis?: string;
    planning_proposal?: string;
    planning_synthesis?: string;
    audit_prompt?: string;
    monitoring_prompt?: string;
    [key: string]: string | undefined;
  };
}

export interface RunUnitSettings {
  enabled?: boolean;
  description?: string;
  system_prompt?: string;
  llm_chain?: string[];
  llm_provider?: string;
  llm_model?: string;
  allow_parallel?: boolean;
  max_parallel?: number;
}

export interface RunSettings {
  main_runs?: Record<string, RunUnitSettings>;
  sub_runs?: Record<string, RunUnitSettings>;
  part_runs?: Record<string, RunUnitSettings>;
}

export interface WorkingSessionsConfig {
  enabled: boolean;
  max_concurrent: number;
  preferred_agents: string[];
  queue_non_jules_agent_issues: boolean;
}

// CEO + QA Manager Types
export interface DualCeoConfig {
  enabled: boolean;
  ceo_chain: string[];
  qa_manager_chain: string[];
  max_deliberation_rounds: number;
  deliberation_tasks: string[];
  fallback_to_single: boolean;
  log_deliberations: boolean;
}

// ── Deliberation & Audit Types ──
export interface DeliberationRound {
  phase: string;
  agent: string;
  provider: string;
  duration_ms: number;
  success: boolean;
  content?: string;
}

export interface DeliberationLogEntry {
  deliberation_id: string;
  task_type: string;
  ceo_provider?: string;
  qa_manager_provider?: string;
  alpha_provider?: string; // Legacy
  beta_provider?: string; // Legacy
  consensus_reached: boolean;
  phases_completed: number;
  total_duration_ms: number;
  completed_at: string;
  rounds?: DeliberationRound[];
}

export interface AuditResult {
  session_id: string;
  response: string;
  parsed?: AuditParsed | null;
  updated_at: string;
}

export interface AuditParsed {
  issues_found?: boolean;
  dashboard_escalation?: string;
  remediation_command?: string;
  [key: string]: unknown;
}

export interface OptimizerProposal {
  id?: string;
  title?: string;
  description?: string;
  impact?: string;
  proposed_action?: string;
  created_at?: string;
  approved_at?: string;
  [key: string]: unknown;
}

export interface OptimizerRun {
  next_run_at?: string;
  ran_at?: string;
  summary?: string;
  proposals?: OptimizerProposal[];
  approved_changes?: OptimizerProposal[];
  [key: string]: unknown;
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
