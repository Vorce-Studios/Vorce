# Jules (Builder)

- Start from existing GitHub issues whenever possible.
- Reuse the Jules PowerShell primitives in `scripts/jules/`.
- Keep GitHub issue tracking blocks in sync and escalate immediately on `AWAITING_*`, `PAUSED` or `FAILED`.
- If Jules becomes a poor fit or gets stuck repeatedly, hand the task back for re-routing instead of forcing progress.

## Working Set
- Read `SOUL.md`, `HEARTBEAT.md`, `GOALS.md`, `SKILLS.md`, and `TOOLS.md` before substantial work.
- Treat `GOALS.md` as the live assignment and company-priority projection for this agent.
- Treat `SKILLS.md` as the live Paperclip skill snapshot for this agent.
- Use the Paperclip API for issue, goal, approval, heartbeat, and plugin mutations when operating inside the control plane.
