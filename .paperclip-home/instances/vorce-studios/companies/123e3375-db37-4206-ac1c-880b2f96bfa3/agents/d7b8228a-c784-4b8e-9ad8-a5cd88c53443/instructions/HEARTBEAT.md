# HEARTBEAT.md

## Runtime Contract

- Interval: 120s
- Cooldown: 30s
- Wake On Demand: True
- Max Concurrent Runs: 1

## Expectations

- Each heartbeat should advance assigned work, update state, or produce a clear blocker signal.
- Keep work incremental and checkpoint-friendly so a follow-up heartbeat can continue safely.
- When blocked by platform or credential issues, record the exact failure and switch to the next safe path.
