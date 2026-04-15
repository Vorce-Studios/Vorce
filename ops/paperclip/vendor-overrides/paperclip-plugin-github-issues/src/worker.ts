import type {
  PluginContext,
  PluginWebhookInput,
  ToolResult,
  ToolRunContext,
} from "@paperclipai/plugin-sdk";
import { definePlugin, runWorker } from "@paperclipai/plugin-sdk";
import { JOB_KEYS, TOOL_NAMES } from "./constants.js";
import * as github from "./github.js";
import * as sync from "./sync.js";

let currentContext: PluginContext | null = null;

function getContext(): PluginContext {
  if (!currentContext) {
    throw new Error("Plugin context is not initialized");
  }
  return currentContext;
}

async function resolveToken(ctx: PluginContext): Promise<string> {
  const config = await ctx.config.get();
  const ref = config.githubTokenRef as string | undefined;
  if (!ref) {
    throw new Error("githubTokenRef not configured");
  }
  return ctx.secrets.resolve(ref);
}

function buildToolResult(data: unknown): ToolResult {
  return {
    content: JSON.stringify(data, null, 2),
    data,
  };
}

async function handleGitHubWebhook(input: PluginWebhookInput): Promise<void> {
  const ctx = getContext();
  const eventHeader = input.headers["x-github-event"];
  const eventName = Array.isArray(eventHeader) ? eventHeader[0] : eventHeader;
  const payload = (input.parsedBody ?? JSON.parse(input.rawBody)) as Record<string, unknown>;
  if (!eventName || !payload) {
    return;
  }

  const action = String(payload.action ?? "");
  const issue = payload.issue as Record<string, unknown> | undefined;
  const repository = payload.repository as Record<string, unknown> | undefined;
  const fullName = String(repository?.full_name ?? "");
  if (!issue || !fullName) {
    return;
  }

  const [owner, repo] = fullName.split("/");
  const number = Number(issue.number ?? 0);
  if (!owner || !repo || !number) {
    return;
  }

  const link = await sync.getLinkByGitHub(ctx, owner, repo, number);
  if (!link) {
    return;
  }

  if (eventName === "issues" && (action === "closed" || action === "reopened")) {
    const ghState = (action === "closed" ? "closed" : "open") as "open" | "closed";
    await sync.syncFromGitHub(ctx, link, {
      number: link.ghNumber,
      title: "",
      body: null,
      state: ghState,
      html_url: link.ghHtmlUrl,
      labels: [],
      assignees: [],
      created_at: "",
      updated_at: new Date().toISOString(),
      closed_at: ghState === "closed" ? new Date().toISOString() : null,
    });
    return;
  }

  if (eventName === "issue_comment" && action === "created") {
    const config = await ctx.config.get();
    if (!config.syncComments) {
      return;
    }

    const comment = payload.comment as Record<string, unknown> | undefined;
    const commentBody = String(comment?.body ?? "");
    if (!commentBody || commentBody.includes("[synced from Paperclip]")) {
      return;
    }

    const user = comment?.user as Record<string, unknown> | undefined;
    const commentUser = String(user?.login ?? "github");
    const commentUrl = String(comment?.html_url ?? link.ghHtmlUrl);
    await ctx.issues.createComment(
      link.paperclipIssueId,
      `**@${commentUser}** ([GitHub](${commentUrl})):\n\n${commentBody}`,
      link.paperclipCompanyId,
    );
  }
}

const plugin = definePlugin({
  async setup(ctx) {
    currentContext = ctx;
    ctx.logger.info("GitHub Issues Sync plugin starting");

    ctx.tools.register(TOOL_NAMES.search, {
      displayName: "Search GitHub Issues",
      description: "Search GitHub issues in the configured repository.",
      parametersSchema: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "Search query using GitHub issue search terms.",
          },
          repo: {
            type: "string",
            description: "Optional repository in owner/repo format.",
          },
        },
        required: ["query"],
      },
    }, async (params: unknown) => {
      const p = (params ?? {}) as Record<string, unknown>;
      const token = await resolveToken(ctx);
      const config = await ctx.config.get();
      const repo = String(p.repo ?? config.defaultRepo ?? "").trim();
      const query = String(p.query ?? "").trim();
      if (!repo) {
        return { error: "No repository specified. Pass repo or configure defaultRepo." };
      }
      if (!query) {
        return { error: "query is required." };
      }

      const results = await github.searchIssues(
        ctx.http.fetch.bind(ctx.http),
        token,
        repo,
        query,
      );

      return buildToolResult({
        total_count: results.total_count,
        issues: results.items.map((issue) => ({
          number: issue.number,
          title: issue.title,
          state: issue.state,
          url: issue.html_url,
          labels: issue.labels.map((label) => label.name),
          assignees: issue.assignees.map((assignee) => assignee.login),
          updated_at: issue.updated_at,
        })),
      });
    });

    ctx.tools.register(TOOL_NAMES.link, {
      displayName: "Link GitHub Issue",
      description: "Link a GitHub issue to a Paperclip issue for bidirectional sync.",
      parametersSchema: {
        type: "object",
        properties: {
          ghIssueUrl: {
            type: "string",
            description: "GitHub issue URL or owner/repo#number reference.",
          },
          paperclipIssueId: {
            type: "string",
            description: "Paperclip issue UUID to link.",
          },
        },
        required: ["ghIssueUrl", "paperclipIssueId"],
      },
    }, async (params: unknown, runCtx: ToolRunContext) => {
      const p = (params ?? {}) as Record<string, unknown>;
      const token = await resolveToken(ctx);
      const config = await ctx.config.get();
      const defaultRepo = config.defaultRepo as string | undefined;
      const ghIssueUrl = String(p.ghIssueUrl ?? "").trim();
      const paperclipIssueId = String(p.paperclipIssueId ?? "").trim();
      if (!ghIssueUrl || !paperclipIssueId) {
        return { error: "ghIssueUrl and paperclipIssueId are required." };
      }

      const ref = github.parseGitHubIssueRef(ghIssueUrl, defaultRepo);
      if (!ref) {
        return { error: "Could not parse GitHub issue reference." };
      }

      const existing = await sync.getLink(ctx, paperclipIssueId);
      if (existing) {
        return {
          error: `Paperclip issue is already linked to ${existing.ghOwner}/${existing.ghRepo}#${existing.ghNumber}.`,
        };
      }

      const ghIssue = await github.getIssue(
        ctx.http.fetch.bind(ctx.http),
        token,
        ref.owner,
        ref.repo,
        ref.number,
      );

      const syncDirection =
        (config.syncDirection as sync.IssueLink["syncDirection"]) ||
        "bidirectional";
      const link = await sync.createLink(ctx, {
        paperclipIssueId,
        paperclipCompanyId: runCtx.companyId,
        ghOwner: ref.owner,
        ghRepo: ref.repo,
        ghNumber: ref.number,
        ghHtmlUrl: ghIssue.html_url,
        ghState: ghIssue.state,
        syncDirection,
      });

      return buildToolResult({
        linked: true,
        github_issue: {
          number: ghIssue.number,
          title: ghIssue.title,
          state: ghIssue.state,
          url: ghIssue.html_url,
        },
        sync_direction: link.syncDirection,
      });
    });

    ctx.tools.register(TOOL_NAMES.unlink, {
      displayName: "Unlink GitHub Issue",
      description: "Remove the sync link from a Paperclip issue.",
      parametersSchema: {
        type: "object",
        properties: {
          paperclipIssueId: {
            type: "string",
            description: "Paperclip issue UUID to unlink.",
          },
        },
        required: ["paperclipIssueId"],
      },
    }, async (params: unknown) => {
      const p = (params ?? {}) as Record<string, unknown>;
      const paperclipIssueId = String(p.paperclipIssueId ?? "").trim();
      if (!paperclipIssueId) {
        return { error: "paperclipIssueId is required." };
      }

      const removed = await sync.removeLink(ctx, paperclipIssueId);
      return buildToolResult({ unlinked: removed });
    });

    ctx.events.on("issue.updated", async (event) => {
      const payload = (event.payload ?? {}) as Record<string, unknown>;
      const issueId = String(payload.id ?? "").trim();
      const status = String(payload.status ?? "").trim();
      if (!issueId || !status) {
        return;
      }

      const link = await sync.getLink(ctx, issueId);
      if (!link) {
        return;
      }

      try {
        const token = await resolveToken(ctx);
        await sync.syncToGitHub(ctx, link, status, token);
      } catch (error) {
        ctx.logger.error("Failed to sync status to GitHub", { error: String(error) });
      }
    });

    ctx.events.on("issue.comment.created", async (event) => {
      const config = await ctx.config.get();
      if (!config.syncComments) {
        return;
      }

      const payload = (event.payload ?? {}) as Record<string, unknown>;
      const issueId = String(payload.issueId ?? "").trim();
      const body = String(payload.body ?? "").trim();
      const authorName = String(payload.authorName ?? "Paperclip user").trim();
      if (!issueId || !body) {
        return;
      }

      const link = await sync.getLink(ctx, issueId);
      if (!link) {
        return;
      }

      try {
        const token = await resolveToken(ctx);
        await sync.bridgeCommentToGitHub(ctx, link, token, body, authorName);
      } catch (error) {
        ctx.logger.error("Failed to bridge comment to GitHub", { error: String(error) });
      }
    });

    ctx.jobs.register(JOB_KEYS.periodicSync, async () => {
      ctx.logger.info("Running periodic GitHub sync");
      ctx.logger.info("Periodic sync complete (manual links only; webhook-first mode)");
    });

    ctx.data.register("issue-link", async (params: Record<string, unknown>) => {
      const issueId = String(params.issueId ?? "").trim();
      if (!issueId) {
        return { linked: false };
      }

      const link = await sync.getLink(ctx, issueId);
      if (!link) {
        return { linked: false };
      }

      try {
        const token = await resolveToken(ctx);
        const ghIssue = await github.getIssue(
          ctx.http.fetch.bind(ctx.http),
          token,
          link.ghOwner,
          link.ghRepo,
          link.ghNumber,
        );
        return {
          linked: true,
          github: {
            number: ghIssue.number,
            title: ghIssue.title,
            state: ghIssue.state,
            url: ghIssue.html_url,
            labels: ghIssue.labels.map((label) => label.name),
            assignees: ghIssue.assignees.map((assignee) => assignee.login),
            updated_at: ghIssue.updated_at,
          },
          syncDirection: link.syncDirection,
          lastSyncAt: link.lastSyncAt,
        };
      } catch {
        return {
          linked: true,
          github: {
            number: link.ghNumber,
            url: link.ghHtmlUrl,
            state: link.lastGhState,
          },
          syncDirection: link.syncDirection,
          lastSyncAt: link.lastSyncAt,
          fetchError: true,
        };
      }
    });

    ctx.logger.info("GitHub Issues Sync plugin ready");
  },

  async onHealth() {
    return { status: "ok", message: "GitHub Issues Sync operational" };
  },

  async onValidateConfig(config) {
    const errors: string[] = [];
    if (!config.githubTokenRef) {
      errors.push("githubTokenRef is required");
    }
    if (
      config.defaultRepo &&
      typeof config.defaultRepo === "string" &&
      !config.defaultRepo.includes("/")
    ) {
      errors.push("defaultRepo must be in owner/repo format");
    }
    return { ok: errors.length === 0, errors };
  },

  async onWebhook(input: PluginWebhookInput) {
    await handleGitHubWebhook(input);
  },
});

export default plugin;
runWorker(plugin, import.meta.url);
