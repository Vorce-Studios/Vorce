## 2024-11-20 – Use Hold-to-Confirm for Destructive Actions in Live Environments
**Learning:** MapFlow is used in live-performance scenarios where accidental clicks can cause catastrophic disruptions. Simple buttons are unsafe for actions that erase state, drop data, or clear components globally.
**Action:** Always replace standard `ui.button().clicked()` with `crate::widgets::custom::hold_to_action_button` (using `WARN_COLOR` or `ERROR_COLOR`) for destructive or state-resetting operations in node-based workflows.
