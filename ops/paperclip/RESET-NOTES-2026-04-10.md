# Paperclip Reset Notes - 2026-04-10

## Why This Exists

These notes capture the last known Vorce Paperclip shape before the clean reinstall requested on 2026-04-10.
They are a migration aid only. Old Paperclip config/data files must not be reused as seed state.

## Last Known Company Shape

- Company name: `Vorce-Studios`
- Instance id: `vorce-studios`
- Paperclip version: `2026.403.0`
- Local server target: `127.0.0.1:3144`
- Embedded Postgres target: `5433`

## Previous Agent Set

The prior repo-driven org definition contained 13 roles:

1. `Victor (CEO / Chief Architect)`
2. `Lena (Personal Assistant)`
3. `Leon (Chief of Staff / Capacity Router)`
4. `Noah (Discovery Scout)`
5. `Jules (Builder)`
6. `Julia (Jules Session Monitor)`
7. `Olivia (GitHub PR Monitor)`
8. `Mia (Gemini Reviewer)`
9. `Elias (Qwen Reviewer)`
10. `Caleb (Codex Reviewer)`
11. `Sophia (Ops / Merge Steward)`
12. `Atlas (Context Agent)`
13. `Aria (Antigravity Builder)`

## Previous Control-Plane Intent

- CEO handled architecture, prioritization, escalation, release decisions.
- Chief of Staff handled routing, queue health, wakeups, and escalations.
- Jules handled implementation work.
- Julia monitored Jules sessions.
- Olivia monitored PRs and merge blockers.
- Review and triage were split across Gemini, Qwen, and Codex reviewer lanes.
- Discovery, assistant, atlas, ops, and antigravity added extra specialization.

## Previous Goals

- Mission: ship Vorce as reliable, performant VJ software.
- Goal buckets:
  - stability and quality
  - feature completion for v1
  - developer experience
  - community and release

## Previous Plugin Set

The working plan expected these plugins:

1. `paperclip-plugin-github-issues`
2. `paperclip-plugin-telegram`
3. `paperclip-chat`
4. `yesterday-ai.paperclip-plugin-company-wizard`

## Reset Target

The new clean install should use only four agents:

1. CEO with `codex_local`
2. Auftragsmanagement with Gemini
3. Reviewer/Coder with Qwen
4. Reviewer/Coder with Codex

## Explicit User Constraints For The Rebuild

- CEO absorbs the former Chief-of-Staff responsibilities.
- Auftragsmanagement creates and monitors Jules sessions until PRs exist, then follows PR mergeability.
- Qwen reviewer/coder is on-demand only and reviews only when the CEO explicitly requests it.
- Codex reviewer/coder is for difficult and complex work only, on-demand only.
- Keep the new company lean to save tokens and reduce coordination overhead.
- Do not restore old Paperclip config/data files into the fresh instance.
