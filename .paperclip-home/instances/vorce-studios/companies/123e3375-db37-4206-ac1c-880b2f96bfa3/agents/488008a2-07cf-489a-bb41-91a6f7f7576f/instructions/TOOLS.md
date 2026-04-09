# TOOLS.md

## Control Plane
- Paperclip API: http://127.0.0.1:3144
- Local repository access is available in the current working tree.
- Managed instruction bundle files in this directory are part of the runtime contract.

## Installed Plugins
- paperclip-plugin-github-issues
- paperclip-plugin-telegram
- paperclip-chat
- yesterday-ai.paperclip-plugin-company-wizard

## Usage Rules
- Prefer the Paperclip API for company, issue, approval, skill, and plugin state changes.
- Use plugin capabilities only when the plugin is loaded and configured.
- Keep external side effects explicit and observable from Paperclip state when possible.